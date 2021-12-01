#!/bin/bash
#
# Copyright (c) 2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail


SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_PATH}/../../.ci/lib.sh"
source "${SCRIPT_PATH}/../../lib/common.bash"
source "/etc/os-release" || source "/usr/lib/os-release"

CI=${CI:-""}
RUNTIME=${RUNTIME:-containerd-shim-kata-v2}
RUNTIME_PATH=${RUNTIME_PATH:-$(command -v $RUNTIME)}

system_pod_wait_time=120
sleep_time=5
wait_pods_ready()
{
	# Master components provide the cluster’s control plane, including kube-apisever,
	# etcd, kube-scheduler, kube-controller-manager, etc.
	# We need to ensure their readiness before we run any container tests.
	local pods_status="kubectl get pods --all-namespaces"
	local apiserver_pod="kube-apiserver.*1/1.*Running"
	local controller_pod="kube-controller-manager.*1/1.*Running"
	local etcd_pod="etcd.*1/1.*Running"
	local scheduler_pod="kube-scheduler.*1/1.*Running"
	local dns_pod="coredns.*1/1.*Running"

	local system_pod=($apiserver_pod $controller_pod $etcd_pod $scheduler_pod $dns_pod)
	for pod_entry in "${system_pod[@]}"
	do
		waitForProcess "$system_pod_wait_time" "$sleep_time" "$pods_status | grep $pod_entry"
	done
}

build_custom_stress_image()
{
	info "Build custom stress image"
	image_version=$(get_test_version "docker_images.registry.version")
	registry_image=$(get_test_version "docker_images.registry.registry_url"):"${image_version}"
	arch=$("${SCRIPT_PATH}/../../.ci/kata-arch.sh")
	if [[ "${arch}" == "ppc64le" || "${arch}" == "s390x" ]]; then
		# that image is not built for these architectures
		image_version=$(get_test_version "docker_images.registry_ibm.version")
		registry_image=$(get_test_version "docker_images.registry_ibm.registry_url"):"${image_version}"
	fi

	runtimeclass_files_path="${SCRIPT_PATH}/runtimeclass_workloads"
	pushd "${runtimeclass_files_path}/stress"
	[ "${container_engine}" == "docker" ] && restart_docker_service
	sudo -E "${container_engine}" build . -t "${stress_image}"
	popd

	if [ "${stress_image_pull_policy}" == "Always" ]; then
		info "Store custom stress image in registry"
		sudo -E "${container_engine}" run -d -p ${registry_port}:5000 --restart=always --name "${registry_name}" "${registry_image}"
		# wait for registry container
		waitForProcess 15 3 "curl http://localhost:${registry_port}"
		sudo -E "${container_engine}" push "${stress_image}"
	fi
}

cri_runtime="${CRI_RUNTIME:-crio}"
kubernetes_version=$(get_version "externals.kubernetes.version")

# store iptables if CI running on bare-metal
BAREMETAL="${BAREMETAL:-false}"
iptables_cache="${KATA_TESTS_DATADIR}/iptables_cache"
if [ "${BAREMETAL}" == true ]; then
	[ -d "${KATA_TESTS_DATADIR}" ] || sudo mkdir -p "${KATA_TESTS_DATADIR}"
	# cleanup iptables before save
	iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X
	iptables-save > "$iptables_cache"
fi

case "${cri_runtime}" in
containerd)
	cri_runtime_socket="/run/containerd/containerd.sock"
	cgroup_driver="cgroupfs"
	;;
crio)
	cri_runtime_socket="/var/run/crio/crio.sock"
	cgroup_driver="systemd"
	;;
*)
	echo "Runtime ${cri_runtime} not supported"
	;;
esac

# Check no there are no kata processes from previous tests.
check_processes

# Build and store custom stress image
build_custom_stress_image

# Remove existing CNI configurations:
cni_config_dir="/etc/cni"
cni_interface="cni0"
sudo rm -rf /var/lib/cni/networks/*
sudo rm -rf "${cni_config_dir}"/*
if ip a show "$cni_interface"; then
	sudo ip link set dev "$cni_interface" down
	sudo ip link del "$cni_interface"
fi

echo "Start ${cri_runtime} service"
# stop containerd first and then restart it
info "Stop containerd service"
systemctl is-active --quiet containerd && sudo systemctl stop containerd
sudo systemctl enable --now ${cri_runtime}
max_cri_socket_check=5
wait_time_cri_socket_check=5

for i in $(seq ${max_cri_socket_check}); do
	#when the test runs two times in the CI, the second time crio takes some time to be ready
	sleep "${wait_time_cri_socket_check}"
	if [ -e "${cri_runtime_socket}" ]; then
		break
	fi

	echo "Waiting for cri socket ${cri_runtime_socket} (try ${i})"
done

sudo systemctl status "${cri_runtime}" --no-pager

echo "Init cluster using ${cri_runtime_socket}"
kubeadm_config_template="${SCRIPT_PATH}/kubeadm/config.yaml"
kubeadm_config_file="$(mktemp --tmpdir kubeadm_config.XXXXXX.yaml)"

sed -e "s|CRI_RUNTIME_SOCKET|${cri_runtime_socket}|" "${kubeadm_config_template}" > "${kubeadm_config_file}"
sed -i "s|KUBERNETES_VERSION|v${kubernetes_version/-*}|" "${kubeadm_config_file}"
sed -i "s|CGROUP_DRIVER|${cgroup_driver}|" "${kubeadm_config_file}"

trap 'sudo -E sh -c "rm -r "${kubeadm_config_file}""' EXIT

if [ "${CI}" == true ] && [[ $(wc -l /proc/swaps | awk '{print $1}') -gt 1 ]]; then
	grep -q zram /proc/swaps && echo "# zram swap disabled"  | sudo tee /etc/systemd/zram-generator.conf
	sudo swapoff -a || true
fi

#reinstall kubelet to do deep cleanup
if [ "${BAREMETAL}" == true -a "$(command -v kubelet)" != "" ]; then
	info "reinstall kubeadm, kubelet before initialize k8s"
	bash -f "${SCRIPT_PATH}/../../.ci/install_kubernetes.sh"
fi

sudo -E kubeadm init --config "${kubeadm_config_file}"

mkdir -p "$HOME/.kube"
sudo cp "/etc/kubernetes/admin.conf" "$HOME/.kube/config"
sudo chown $(id -u):$(id -g) "$HOME/.kube/config"
export KUBECONFIG="$HOME/.kube/config"

# enable debug log for kubelet
sudo sed -i 's/.$/ --v=4"/' /var/lib/kubelet/kubeadm-flags.env
echo "Kubelet options:"
sudo cat /var/lib/kubelet/kubeadm-flags.env
sudo systemctl daemon-reload && sudo systemctl restart kubelet

kubectl get nodes
kubectl get pods

# default network plugin should be flannel, and its config file is taken from k8s 1.12 documentation
flannel_version="$(get_test_version "externals.flannel.version")"
flannel_url="https://raw.githubusercontent.com/coreos/flannel/${flannel_version}/Documentation/kube-flannel.yml"

#Load arch-specific configure file
if [ -f "${SCRIPT_PATH}/../../.ci/${arch}/kubernetes/init.sh" ]; then
        source "${SCRIPT_PATH}/../../.ci/${arch}/kubernetes/init.sh"
fi

network_plugin_config=${network_plugin_config:-$flannel_url}

kubectl apply -f "$network_plugin_config"

# we need to ensure a few specific pods ready and running
wait_pods_ready

echo "Create kata RuntimeClass resource"
kubectl create -f "${runtimeclass_files_path}/kata-runtimeclass.yaml"

# Enable the master node to be able to schedule pods.
kubectl taint nodes "$(hostname)" node-role.kubernetes.io/master:NoSchedule-
