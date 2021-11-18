#!/bin/bash
#
# Copyright (c) 2017-2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_PATH}/../../../lib/common.bash"
source "${SCRIPT_PATH}/../../../.ci/lib.sh"

# runc is installed in /usr/local/sbin/ add that path
export PATH="$PATH:/usr/local/sbin"

containerd_tarball_version=$(get_version "externals.containerd.version")

# Runtime to be used for testing
RUNTIME=${RUNTIME:-containerd-shim-kata-v2}
SHIMV2_TEST=${SHIMV2_TEST:-""}
FACTORY_TEST=${FACTORY_TEST:-""}
KILL_VMM_TEST=${KILL_VMM_TEST:-""}
KATA_HYPERVISOR="${KATA_HYPERVISOR:-qemu}"
ARCH=$(uname -m)

default_runtime_type="io.containerd.runc.v2"
# Type of containerd runtime to be tested
containerd_runtime_type="${default_runtime_type}"
# Runtime to be use for the test in containerd
containerd_runtime_test=${RUNTIME}
if [ -n "${SHIMV2_TEST}" ]; then
	containerd_runtime_type="io.containerd.kata.v2"
	containerd_runtime_test="io.containerd.kata.v2"
fi

readonly runc_runtime_bin=$(command -v "runc")

readonly CRITEST=${GOPATH}/bin/critest

# Flag to do tasks for CI
SNAP_CI=${SNAP_CI:-""}
CI=${CI:-""}

containerd_shim_path="$(command -v containerd-shim)"
readonly cri_containerd_repo=$(get_version "externals.containerd.url")

#containerd config file
readonly tmp_dir=$(mktemp -t -d test-cri-containerd.XXXX)
export REPORT_DIR="${tmp_dir}"
readonly CONTAINERD_CONFIG_FILE="${tmp_dir}/test-containerd-config"
readonly default_containerd_config="/etc/containerd/config.toml"
readonly default_containerd_config_backup="$CONTAINERD_CONFIG_FILE.backup"
readonly kata_config="/etc/kata-containers/configuration.toml"
readonly default_kata_config="/usr/share/defaults/kata-containers/configuration.toml"

ci_config() {
	sudo mkdir -p $(dirname "${kata_config}")
	sudo cp "${default_kata_config}" "${kata_config}"

	source /etc/os-release || source /usr/lib/os-release
	ID=${ID:-""}
	if [ "$ID" == ubuntu ] &&  [ -n "${CI}" ] ;then
		# https://github.com/kata-containers/tests/issues/352
		if [ -n "${FACTORY_TEST}" ]; then
			sudo sed -i -e 's/^#enable_template.*$/enable_template = true/g' "${kata_config}"
			echo "init vm template"
			sudo -E PATH=$PATH "$RUNTIME" factory init
		fi
	fi

	if [ -n "${CI}" ]; then
		(
		echo "Install cni config"
		${SCRIPT_PATH}/../../../.ci/configure_cni.sh
		)
	fi

	echo "enable debug for kata-runtime"
	sudo sed -i 's/^#enable_debug =/enable_debug =/g' ${kata_config}
	sudo sed -i 's/^#enable_debug =/enable_debug =/g' ${default_kata_config}
}

ci_cleanup() {
	source /etc/os-release || source /usr/lib/os-release

	if [ -n "${FACTORY_TEST}" ]; then
		echo "destroy vm template"
		sudo -E PATH=$PATH "$RUNTIME" factory destroy
	fi

	if [ -n "${KILL_VMM_TEST}" ] && [ -e "$default_containerd_config_backup" ]; then
		echo "restore containerd config"
		sudo systemctl stop containerd
		sudo cp "$default_containerd_config_backup" "$default_containerd_config"
	fi

	ID=${ID:-""}
	if [ "$ID" == ubuntu ]; then
		if [ -n "${SNAP_CI}" ]; then
			# restore default configuration
			sudo cp "${default_kata_config}" "${kata_config}"
		elif [ -n "${CI}" ] ;then
			[ -f "${kata_config}" ] && sudo rm "${kata_config}"
		fi
	fi
}

create_containerd_config() {
	local runtime="$1"
	# kata_annotations is set to 1 if caller want containerd setup with
	# kata annotations support.
	local kata_annotations=${2-0}
	[ -n "${runtime}" ] || die "need runtime to create config"

	local runtime_type="${containerd_runtime_type}"
	if [ "${runtime}" == "runc" ]; then
		runtime_type="io.containerd.runc.v2"
	fi
	local containerd_runtime="${runtime}"
	if [ "${runtime_type}" == "${default_runtime_type}" ];then
		local containerd_runtime=$(command -v "${runtime}")
	fi
	# Remove dots.  Dots are used by toml syntax as atribute separator
	runtime="${runtime//./-}"

cat << EOT | sudo tee "${CONTAINERD_CONFIG_FILE}"
[plugins]
  [plugins.cri]
    [plugins.cri.containerd]
        default_runtime_name = "$runtime"
      [plugins.cri.containerd.runtimes.${runtime}]
        runtime_type = "${runtime_type}"
        $( [ $kata_annotations -eq 1 ] && \
        echo 'pod_annotations = ["io.katacontainers.*"]' && \
        echo '        container_annotations = ["io.katacontainers.*"]'
        )
        [plugins.cri.containerd.runtimes.${runtime}.options]
          Runtime = "${containerd_runtime}"
[plugins.linux]
       shim = "${containerd_shim_path}"
EOT

if [ "$KATA_HYPERVISOR" == "firecracker" ]; then
	sudo sed -i 's|^\(\[plugins\]\).*|\1\n  \[plugins.devmapper\]\n    pool_name = \"contd-thin-pool\"\n    base_image_size = \"4096MB\"|' ${CONTAINERD_CONFIG_FILE}
	echo "Devicemapper configured"
	cat "${CONTAINERD_CONFIG_FILE}"
fi

}

cleanup() {
	ci_cleanup
	[ -d "$tmp_dir" ] && rm -rf "${tmp_dir}"
}

trap cleanup EXIT

err_report() {
	local log_file="${REPORT_DIR}/containerd.log"
	if [ -f "$log_file" ]; then
		echo "ERROR: containerd log :"
		echo "-------------------------------------"
		cat "${log_file}"
		echo "-------------------------------------"
	fi
}

trap err_report ERR

check_daemon_setup() {
	info "containerd(cri): Check daemon works with runc"
	create_containerd_config "runc"

	#restart docker service as TestImageLoad depends on it
	[ -z "${USE_PODMAN:-}" ] && restart_docker_service

	sudo -E PATH="${PATH}:/usr/local/bin" \
		REPORT_DIR="${REPORT_DIR}" \
		FOCUS="TestImageLoad" \
		RUNTIME="" \
		CONTAINERD_CONFIG_FILE="$CONTAINERD_CONFIG_FILE" \
		make -e cri-integration
}

testContainerStart() {
	# no_container_yaml set to 1 will not create container_yaml
	# because caller has created its own container_yaml.
	no_container_yaml=${1-0}

	local pod_yaml=${REPORT_DIR}/pod.yaml
	local container_yaml=${REPORT_DIR}/container.yaml
	local image="busybox:latest"

	cat << EOF > "${pod_yaml}"
metadata:
  name: busybox-sandbox1
EOF

	#TestContainerSwap has created its own container_yaml.
	if [ $no_container_yaml -ne 1 ]; then
		cat << EOF > "${container_yaml}"
metadata:
  name: busybox-killed-vmm
image:
  image: "$image"
command:
- top
EOF
	fi

	sudo cp "$default_containerd_config" "$default_containerd_config_backup"
	sudo cp $CONTAINERD_CONFIG_FILE "$default_containerd_config"

	restart_containerd_service

	sudo crictl pull $image
	podid=$(sudo crictl runp $pod_yaml)
	cid=$(sudo crictl create $podid $container_yaml $pod_yaml)
	sudo crictl start $cid
}

testContainerStop() {
	info "stop pod $podid"
	sudo crictl stopp $podid
	info "remove pod $podid"
	sudo crictl rmp $podid

	sudo cp "$default_containerd_config_backup" "$default_containerd_config"
	restart_containerd_service
}

TestKilledVmmCleanup() {
	if [ -z "${SHIMV2_TEST}" ] || [ -z "${KILL_VMM_TEST}" ]; then
		return
	fi

	info "test killed vmm cleanup"

	testContainerStart

	qemu_pid=$(ps aux|grep qemu|grep -v grep|awk '{print $2}')
	info "kill qemu $qemu_pid"
	sudo kill -SIGKILL $qemu_pid
	# sleep to let shimv2 exit
	sleep 1
	remained=$(ps aux|grep shimv2|grep -v grep || true)
	[ -z $remained ] || die "found remaining shimv2 process $remained"

	testContainerStop

	info "stop containerd"
}

TestContainerMemoryUpdate() {
	if [[ "${KATA_HYPERVISOR}" != "qemu" ]] || [[ "${ARCH}" == "ppc64le" ]] || [[ "${ARCH}" == "s390x" ]]; then
		return
	fi

	test_virtio_mem=$1

	if [ $test_virtio_mem -eq 1 ]; then
		if [[ "$ARCH" != "x86_64" ]]; then
			return
		fi
		info "Test container memory update with virtio-mem"

		sudo sed -i -e 's/^#enable_virtio_mem.*$/enable_virtio_mem = true/g' "${kata_config}"
	else
		info "Test container memory update without virtio-mem"

		sudo sed -i -e 's/^enable_virtio_mem.*$/#enable_virtio_mem = true/g' "${kata_config}"
	fi

	testContainerStart

	vm_size=$(($(crictl exec $cid cat /proc/meminfo | grep "MemTotal:" | awk '{print $2}')*1024))
	if [ $vm_size -gt $((2*1024*1024*1024)) ] || [ $vm_size -lt $((2*1024*1024*1024-128*1024*1024)) ]; then
		testContainerStop
		die "The VM memory size $vm_size before update is not right"
	fi

	sudo crictl update --memory $((2*1024*1024*1024)) $cid
	sleep 1

	vm_size=$(($(crictl exec $cid cat /proc/meminfo | grep "MemTotal:" | awk '{print $2}')*1024))
	if [ $vm_size -gt $((4*1024*1024*1024)) ] || [ $vm_size -lt $((4*1024*1024*1024-128*1024*1024)) ]; then
		testContainerStop
		die "The VM memory size $vm_size after increase is not right"
	fi

	if [ $test_virtio_mem -eq 1 ]; then
		sudo crictl update --memory $((1*1024*1024*1024)) $cid
		sleep 1

		vm_size=$(($(crictl exec $cid cat /proc/meminfo | grep "MemTotal:" | awk '{print $2}')*1024))
		if [ $vm_size -gt $((3*1024*1024*1024)) ] || [ $vm_size -lt $((3*1024*1024*1024-128*1024*1024)) ]; then
			testContainerStop
			die "The VM memory size $vm_size after decrease is not right"
		fi
	fi

	testContainerStop
}

getContainerSwapInfo() {
	swap_size=$(($(crictl exec $cid cat /proc/meminfo | grep "SwapTotal:" | awk '{print $2}')*1024))
	swappiness=$(crictl exec $cid cat /proc/sys/vm/swappiness)
	swap_in_bytes=$(crictl exec $cid cat /sys/fs/cgroup/memory/memory.memsw.limit_in_bytes)
}

TestContainerSwap() {
	if [[ "${KATA_HYPERVISOR}" != "qemu" ]] || [[ "${ARCH}" != "x86_64" ]]; then
		return
	fi

	local container_yaml=${REPORT_DIR}/container.yaml

	info "Test container with guest swap"

	create_containerd_config "${containerd_runtime_test}" 1
	sudo sed -i -e 's/^#enable_guest_swap.*$/enable_guest_swap = true/g' "${kata_config}"

	# Test without swap device
	testContainerStart
	getContainerSwapInfo
	# Current default swappiness is 60
	if [ $swappiness -ne 60 ]; then
		testContainerStop
		die "The VM swappiness $swappiness without swap device is not right"
	fi
	if [ $swap_in_bytes -lt 1125899906842624 ]; then
		testContainerStop
		die "The VM swap_in_bytes $swap_in_bytes without swap device is not right"
	fi
	if [ $swap_size -ne 0 ]; then
		testContainerStop
		die "The VM swap size $swap_size without swap device is not right"
	fi
	testContainerStop

	# Test with swap device
	cat << EOF > "${container_yaml}"
metadata:
  name: busybox-killed-vmm
annotations:
  io.katacontainers.container.resource.swappiness: "100"
  io.katacontainers.container.resource.swap_in_bytes: "1610612736"
linux:
  resources:
    memory_limit_in_bytes: 1073741824
image:
  image: "$image"
command:
- top
EOF
	testContainerStart 1
	getContainerSwapInfo
	if [ $swappiness -ne 100 ]; then
		testContainerStop
		die "The VM swappiness $swappiness with swap device is not right"
	fi
	if [ $swap_in_bytes -ne 1610612736 ]; then
		testContainerStop
		die "The VM swap_in_bytes $swap_in_bytes with swap device is not right"
	fi
	if [ $swap_size -ne 536870912 ]; then
		testContainerStop
		die "The VM swap size $swap_size with swap device is not right"
	fi
	testContainerStop

	# Test without swap_in_bytes
	cat << EOF > "${container_yaml}"
metadata:
  name: busybox-killed-vmm
annotations:
  io.katacontainers.container.resource.swappiness: "100"
linux:
  resources:
    memory_limit_in_bytes: 1073741824
image:
  image: "$image"
command:
- top
EOF
	testContainerStart 1
	getContainerSwapInfo
	if [ $swappiness -ne 100 ]; then
		testContainerStop
		die "The VM swappiness $swappiness without swap_in_bytes is not right"
	fi
	# swap_in_bytes is not set, it should be a value that bigger than 1125899906842624
	if [ $swap_in_bytes -lt 1125899906842624 ]; then
		testContainerStop
		die "The VM swap_in_bytes $swap_in_bytes without swap_in_bytes is not right"
	fi
	if [ $swap_size -ne 1073741824 ]; then
		testContainerStop
		die "The VM swap size $swap_size without swap_in_bytes is not right"
	fi
	testContainerStop

	# Test without memory_limit_in_bytes
	cat << EOF > "${container_yaml}"
metadata:
  name: busybox-killed-vmm
annotations:
  io.katacontainers.container.resource.swappiness: "100"
image:
  image: "$image"
command:
- top
EOF
	testContainerStart 1
	getContainerSwapInfo
	if [ $swappiness -ne 100 ]; then
		testContainerStop
		die "The VM swappiness $swappiness without memory_limit_in_bytes is not right"
	fi
	# swap_in_bytes is not set, it should be a value that bigger than 1125899906842624
	if [ $swap_in_bytes -lt 1125899906842624 ]; then
		testContainerStop
		die "The VM swap_in_bytes $swap_in_bytes without memory_limit_in_bytes is not right"
	fi
	if [ $swap_size -ne 2147483648 ]; then
		testContainerStop
		die "The VM swap size $swap_size without memory_limit_in_bytes is not right"
	fi
	testContainerStop

	create_containerd_config "${containerd_runtime_test}"
}

# k8s may restart docker which will impact on containerd stop
stop_containerd() {
	local tmp=$(pgrep kubelet || true)
	[ -n "$tmp" ] && sudo kubeadm reset -f

	sudo systemctl stop containerd
}

main() {

	info "Stop crio service"
	systemctl is-active --quiet crio && sudo systemctl stop crio

	info "Stop containerd service"
	systemctl is-active --quiet containerd && stop_containerd

	# Configure enviroment if running in CI
	ci_config

	# make sure cri-containerd test install the proper critest version its testing
	rm -f "${CRITEST}"

	go get -d ${cri_containerd_repo}
	pushd "${GOPATH}/src/${cri_containerd_repo}"

	git reset HEAD

	# In CCv0 we are using a fork of containerd, so pull the matching branch of this
	containerd_branch=$(get_version "externals.containerd.branch")
	git checkout "${containerd_branch}"
	
	# switch to the default pause image set by containerd:1.6.x
	sed -i 's#k8s.gcr.io/pause:3.[0-9]#k8s.gcr.io/pause:3.6#' integration/main_test.go
	cp "${SCRIPT_PATH}/container_restart_test.go.patch" ./integration/container_restart_test.go

	# Make sure the right artifacts are going to be built
	make clean

	check_daemon_setup

	info "containerd(cri): testing using runtime: ${containerd_runtime_test}"

	create_containerd_config "${containerd_runtime_test}"

	info "containerd(cri): Running cri-integration"

	passing_test=(
	TestContainerStats
	TestContainerRestart
	TestContainerListStatsWithIdFilter
	TestContainerListStatsWithIdSandboxIdFilter
	TestDuplicateName
	TestImageLoad
	TestImageFSInfo
	TestSandboxCleanRemove
	)

	if [[ "${KATA_HYPERVISOR}" == "cloud-hypervisor" || \
		"${KATA_HYPERVISOR}" == "qemu" ]]; then
		issue="https://github.com/kata-containers/tests/issues/2318"
		info "${KATA_HYPERVISOR} fails with TestContainerListStatsWithSandboxIdFilter }"
		info "see ${issue}"
	else
		passing_test+=("TestContainerListStatsWithSandboxIdFilter")
	fi

	for t in "${passing_test[@]}"
	do
		sudo -E PATH="${PATH}:/usr/local/bin" \
			REPORT_DIR="${REPORT_DIR}" \
			FOCUS="${t}" \
			RUNTIME="" \
			CONTAINERD_CONFIG_FILE="$CONTAINERD_CONFIG_FILE" \
			make -e cri-integration
	done

	TestContainerMemoryUpdate 1
	TestContainerMemoryUpdate 0

	TestKilledVmmCleanup

	popd
}

main