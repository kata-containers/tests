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

# Whether running on bare-metal mode or not.
BAREMETAL="${BAREMETAL:-false}"
CI=${CI:-""}
CI_JOB=${CI_JOB:-}
# Path to the cluster network configuration file. Some architectures will
# overwritten that variable.
network_plugin_config="${network_plugin_config:-}"
RUNTIME=${RUNTIME:-containerd-shim-kata-v2}
RUNTIME_PATH=${RUNTIME_PATH:-$(command -v $RUNTIME)}
CRI_RUNTIME="${CRI_RUNTIME:-crio}"

untaint_node() {
	# Enable the master node to be able to schedule pods.
	local node_name="$(hostname | awk '{print tolower($0)}')"
	local get_taints="kubectl get 'node/${node_name}' -o jsonpath='{.spec.taints}'"
	if eval $get_taints | grep -q 'NoSchedule'; then
		info "Taint 'NoSchedule' is found. Untaint the node so pods can be scheduled."
		kubectl taint nodes "${node_name}" \
			node-role.kubernetes.io/master:NoSchedule-
	fi
	if eval $get_taints | grep -q 'control-plane'; then
		info "Taint 'control-plane' is found. Untaint the node so pods can be scheduled."
		kubectl taint nodes "${node_name}" \
			node-role.kubernetes.io/control-plane-
	fi
}

wait_pods_ready()
{
	# Master components provide the cluster’s control plane, including kube-apisever,
	# etcd, kube-scheduler, kube-controller-manager, etc.
	# We need to ensure their readiness before we run any container tests.
	local pods_status="kubectl get pods --all-namespaces"
	local apiserver_pod="kube-apiserver"
	local controller_pod="kube-controller-manager"
	local etcd_pod="etcd"
	local scheduler_pod="kube-scheduler"
	local dns_pod="coredns"
	local system_pod=($apiserver_pod $controller_pod $etcd_pod $scheduler_pod $dns_pod)

	local system_pod_wait_time=120
	local sleep_time=5
	local running_pattern=""
	for pod_entry in "${system_pod[@]}"
	do
		running_pattern="${pod_entry}.*1/1.*Running"
		if ! waitForProcess "$system_pod_wait_time" "$sleep_time" \
			"$pods_status | grep "${running_pattern}""; then
			info "Some expected Pods aren't running after ${system_pod_wait_time} seconds." 1>&2
			${pods_status} 1>&2
			# Print debug information for the problematic pods.
			for pod in $(kubectl get pods --all-namespaces \
				-o jsonpath='{.items[*].metadata.name}'); do
				if [[ "$pod" =~ ${pod_entry} ]]; then
					echo "[DEBUG] Pod ${pod}:" 1>&2
					kubectl describe -n kube-system \
						pod $pod 1>&2 || true
				fi
			done
			die "Kubernetes is not fully ready. Bailing out..."
		fi
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
	if [ "$(uname -m)" != "s390x" ] && [ "$(uname -m)" != "ppc64le" ] && [ "$(uname -m)" != "aarch64" ] && [ "$ID" != "fedora" }; then
		pushd "${GOPATH}/src/github.com/kata-containers/tests/metrics/density/sysbench-dockerfile"
		registry_port="5000"
		sysbench_image="localhost:${registry_port}/sysbench-kata:latest"
		sudo -E "${container_engine}" build . -t "${sysbench_image}"
		sudo -E "${container_engine}" push "${sysbench_image}"
		popd
	fi
}

# Delete the CNI configuration files and delete the interface.
# That's needed because `kubeadm reset` (ran on clean up) won't clean up the
# CNI configuration and we must ensure a fresh environment before starting
# Kubernetes.
cleanup_cni_configuration() {
	# Remove existing CNI configurations:
	local cni_config_dir="/etc/cni"
	local cni_interface="cni0"
	sudo rm -rf /var/lib/cni/networks/*
	sudo rm -rf "${cni_config_dir}"/*
	if ip a show "$cni_interface"; then
		sudo ip link set dev "$cni_interface" down
		sudo ip link del "$cni_interface"
	fi
}

# Configure the cluster network.
#
# Parameters:
#	$1 - path to the network plugin configuration file (Optional).
#	     Defaults to flannel.
#
configure_network() {
	local network_plugin_config="${1:-}"
	local issue="https://github.com/kata-containers/tests/issues/4381"

	if [ -z "${network_plugin_config}" ]; then
		# default network plugin should be flannel, and its config file is taken from k8s 1.12 documentation
		local flannel_version="$(get_test_version "externals.flannel.version")"
		local flannel_url="$(get_test_version "externals.flannel.kube-flannel_url")"
		info "Use flannel ${flannel_version}"
		network_plugin_config="$flannel_url"
	fi
	info "Use configuration file from ${network_plugin_config}"
	kubectl apply -f "$network_plugin_config"

	if [ -n "${flannel_version:-}" ]; then
		# There is an issue hitting some CI jobs due to a bug on CRI-O that
		# sometimes doesn't realize a new CNI configuration was installed.
		# Here we try a simple workaround which consist of rebooting the
		# CRI-O service.
		if [ "${CRI_RUNTIME:-}" = "crio" ]; then
			info "Restart the CRI-O service due to $issue"
			sudo systemctl restart crio
		fi
		local list_pods="kubectl get -n kube-system --selector app=flannel pods"
		info "Wait for Flannel pods to show up"
		waitForProcess "60" "10" \
			"[ \$($list_pods 2>/dev/null | wc -l) -gt 0 ]"
		local flannel_p
		for flannel_p in $($list_pods \
			-o jsonpath='{.items[*].metadata.name}'); do
			info "Wait for pod $flannel_p be ready"
			if ! kubectl wait -n kube-system --for=condition=Ready \
				"pod/$flannel_p"; then
				info "Flannel pod $flannel_p failed to start"
				echo "[DEBUG] Pod ${flannel_p}:" 1>&2
				kubectl describe -n kube-system "pod/$flannel_p"
			fi
		done
	fi
}

# Save the current iptables configuration.
#
# Global variables:
# 	KATA_TESTS_DATADIR - directory where to save the configuration (mandatory).
#
save_iptables() {
	[ -n "${KATA_TESTS_DATADIR:-}" ] || \
		die "\$KATA_TESTS_DATADIR is empty, unable to save the iptables configuration"

	local iptables_cache="${KATA_TESTS_DATADIR}/iptables_cache"
	[ -d "${KATA_TESTS_DATADIR}" ] || sudo mkdir -p "${KATA_TESTS_DATADIR}"
	# cleanup iptables before save
	iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X
	iptables-save > "$iptables_cache"
}

# Start Kubernetes
#
# Parameters:
#	$1 - Kubernetes version as in versions.yaml (mandatory).
#	$2 - CRI runtime socket path (mandatory).
#	$3 - cgroup driver name (mandatory).
# Global variables:
#	SCRIPT_PATH - path to this script.
#	kubeadm_config_file - the kubeadmin configuration file created in
#			      this function.
#	KUBECONFIG - exported by this function.
#
start_kubernetes() {
	local k8s_version="$1"
	local cri_socket_path="$2"
	local cgroup_driver="$3"
	local kubeadm_config_template="${SCRIPT_PATH}/kubeadm/config.yaml"
	local kubelet_wait="240"
	local kubelet_sleep="10"

	info "Init cluster using ${cri_socket_path}"

	# This should be global otherwise the clean up fails.
	kubeadm_config_file="$(mktemp --tmpdir kubeadm_config.XXXXXX.yaml)"
	trap 'sudo -E sh -c "rm -r "${kubeadm_config_file}""' EXIT

	sed -e "s|CRI_RUNTIME_SOCKET|${cri_socket_path}|" "${kubeadm_config_template}" > "${kubeadm_config_file}"
	sed -i "s|KUBERNETES_VERSION|v${k8s_version/-*}|" "${kubeadm_config_file}"
	sed -i "s|CGROUP_DRIVER|${cgroup_driver}|" "${kubeadm_config_file}"

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

	info "Probing kubelet (timeout=${kubelet_wait}s)"
	waitForProcess "$kubelet_wait" "$kubelet_sleep" \
		"kubectl get nodes"
}

# Start the CRI runtime service.
#
# Arguments:
#	$1 - the CRI service name (mandatory).
#	$2 - the expected service socket path (mandatory).
#
start_cri_runtime_service() {
	local cri=$1
	local socket_path=$2
	# Number of check tentatives.
	local max_cri_socket_check=5
	# Sleep time between checks.
	local wait_time_cri_socket_check=5

	# stop containerd first and then restart it
	if systemctl is-active --quiet containerd; then
		info "Stop containerd service"
		sudo systemctl stop containerd
	fi

	sudo systemctl enable --now ${cri}

	for i in $(seq ${max_cri_socket_check}); do
		#when the test runs two times in the CI, the second time crio takes some time to be ready
		sleep "${wait_time_cri_socket_check}"
		[ -e "${socket_path}" ] && break
		info "Waiting for cri socket ${socket_path} (try ${i})"
	done

	sudo systemctl status "${cri}" --no-pager || \
		die "Unable to start the ${cri} service"
}

main() {
	local arch="$("${SCRIPT_PATH}/../../.ci/kata-arch.sh")"
	local kubernetes_version=$(get_version "externals.kubernetes.version")
	local cri_runtime_socket=""
	local cgroup_driver=""

	case "${CRI_RUNTIME}" in
	containerd)
		cri_runtime_socket="/run/containerd/containerd.sock"
		cgroup_driver="cgroupfs"
		;;
	crio)
		cri_runtime_socket="/var/run/crio/crio.sock"
		cgroup_driver="systemd"
		;;
	*)
		die "Runtime ${CRI_RUNTIME} not supported"
		;;
	esac

        #Load arch-specific configure file
	if [ -f "${SCRIPT_PATH}/../../.ci/${arch}/kubernetes/init.sh" ]; then
		source "${SCRIPT_PATH}/../../.ci/${arch}/kubernetes/init.sh"
	fi

	# store iptables if CI running on bare-metal. The configuration should be
	# restored afterwards the tests finish.
	if [ "${BAREMETAL}" == true ]; then
		info "Save the iptables configuration"
		save_iptables
	fi

	info "Check there aren't dangling processes from previous tests"
	check_processes

	# Build and store custom stress image
	build_custom_stress_image

	info "Clean up any leftover CNI configuration"
	cleanup_cni_configuration

	if [ "$CRI_RUNTIME" == crio ]; then
		crio_repository="github.com/cri-o/cri-o"
		crio_repository_path="$GOPATH/src/${crio_repository}"
		cni_directory="/etc/cni/net.d"
		if [ ! -d "${cni_directory}" ]; then
			sudo mkdir -p "${cni_directory}"
		fi
		sudo cp "${crio_repository_path}/contrib/cni/10-crio-bridge.conf" "${cni_directory}"
	fi

	info "Start ${CRI_RUNTIME} service"
	start_cri_runtime_service "${CRI_RUNTIME}" "${cri_runtime_socket}"

	info "Start Kubernetes"
	start_kubernetes "${kubernetes_version}" "${cri_runtime_socket}" "${cgroup_driver}"

	info "Configure the cluster network"
	configure_network "${network_plugin_config}"

	# we need to ensure a few specific pods ready and running
	info "Wait for system's pods be ready and running"
	wait_pods_ready

	info "Create kata RuntimeClass resource"
	kubectl create -f "${runtimeclass_files_path}/kata-runtimeclass.yaml"

	untaint_node
}

main $@
