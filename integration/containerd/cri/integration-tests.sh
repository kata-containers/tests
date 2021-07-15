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

# runc is installed in /usr/local/sbin/ add that path
export PATH="$PATH:/usr/local/sbin"

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
readonly cri_containerd_repo="github.com/containerd/containerd"
readonly cri_repo="github.com/containerd/cri"

#containerd config file
readonly tmp_dir=$(mktemp -t -d test-cri-containerd.XXXX)
export REPORT_DIR="${tmp_dir}"
readonly CONTAINERD_CONFIG_FILE="${tmp_dir}/test-containerd-config"
readonly default_containerd_config="/etc/containerd/config.toml"
readonly default_containerd_config_backup="$CONTAINERD_CONFIG_FILE.backup"
readonly kata_config="/etc/kata-containers/configuration.toml"
readonly default_kata_config="/usr/share/defaults/kata-containers/configuration.toml"

info() {
	echo -e "INFO: $*"
}

die() {
	echo >&2 "ERROR: $*"
	exit 1
}

ci_config() {
	source /etc/os-release || source /usr/lib/os-release
	ID=${ID:-""}
	if [ "$ID" == ubuntu ] &&  [ -n "${CI}" ] ;then
		# https://github.com/kata-containers/tests/issues/352
		sudo mkdir -p $(dirname "${kata_config}")
		sudo cp "${default_kata_config}" "${kata_config}"
		if [ -n "${FACTORY_TEST}" ]; then
			sudo sed -i -e 's/^#enable_template.*$/enable_template = true/g' "${kata_config}"
			echo "init vm template"
			sudo -E PATH=$PATH "$RUNTIME" factory init
		fi
	fi

	SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
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
	[ -d "$tmp_dir" ] && rm -rf "${tmp_dir}"
	ci_cleanup
}

trap cleanup EXIT

err_report() {
	echo "ERROR: containerd log :"
	echo "-------------------------------------"
	cat "${REPORT_DIR}/containerd.log"
	echo "-------------------------------------"
}

trap err_report ERR

restart_docker() {
	info "restart docker service"

	back_file=$(mktemp)

	#avoid the "Start request repeated too quickly" error
        if [ -f "/lib/systemd/system/docker.service" ]; then
		cp /lib/systemd/system/docker.service ${back_file}
                sudo sed -i 's/StartLimitBurst.*$/StartLimitBurst=0/g' /lib/systemd/system/docker.service
        elif [ -f "/usr/lib/systemd/system/docker.service" ]; then
		cp /usr/lib/systemd/system/docker.service ${back_file}
                sudo sed -i 's/StartLimitBurst.*$/StartLimitBurst=0/g' /usr/lib/systemd/system/docker.service
        fi
        sudo systemctl daemon-reload
        sudo systemctl restart docker

	#recover docker service file
	if [ -f "/lib/systemd/system/docker.service" ]; then
		sudo mv ${back_file} /lib/systemd/system/docker.service
	elif [ -f "/usr/lib/systemd/system/docker.service" ]; then
		sudo mv ${back_file} /usr/lib/systemd/system/docker.service
	fi
        sudo systemctl daemon-reload
}

check_daemon_setup() {
	info "containerd(cri): Check daemon works with runc"
	create_containerd_config "runc"

	#restart docker service as TestImageLoad depends on it
	[ -z "${USE_PODMAN:-}" ] && restart_docker

	sudo -E PATH="${PATH}:/usr/local/bin" \
		REPORT_DIR="${REPORT_DIR}" \
		FOCUS="TestImageLoad" \
		RUNTIME="" \
		CONTAINERD_CONFIG_FILE="$CONTAINERD_CONFIG_FILE" \
		make -e test-integration
}

testContainerStart() {
	local pod_yaml=${REPORT_DIR}/pod.yaml
	local container_yaml=${REPORT_DIR}/container.yaml
	local image="busybox:latest"

	cat << EOF > "${pod_yaml}"
metadata:
  name: busybox-sandbox1
EOF

	cat << EOF > "${container_yaml}"
metadata:
  name: busybox-killed-vmm
image:
  image: "$image"
command:
- top
EOF

	sudo cp "$default_containerd_config" "$default_containerd_config_backup"
	sudo cp $CONTAINERD_CONFIG_FILE "$default_containerd_config"

	sudo systemctl restart containerd

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
	sudo systemctl restart containerd
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

main() {

	info "Stop crio service"
	systemctl is-active --quiet crio && sudo systemctl stop crio

	info "Stop containerd service"
	systemctl is-active --quiet containerd && sudo systemctl stop containerd

	# Configure enviroment if running in CI
	ci_config

	# make sure cri-containerd test install the proper critest version its testing
	rm -f "${CRITEST}"

	go get ${cri_repo}
	pushd "${GOPATH}/src/${cri_repo}"

	git reset HEAD
	git checkout master
	# switch to the default pause image set by containerd:1.5.x
	sed -i 's#k8s.gcr.io/pause:3.[0-9]#k8s.gcr.io/pause:3.5#' integration/main_test.go
	cp "${SCRIPT_PATH}/container_restart_test.go.patch" ./integration/container_restart_test.go

	#test cri using the built/installed containerd instead of containerd built in cri
	sed -i 's#${ROOT}/_output/containerd#/usr/local/bin/containerd#' hack/test-utils.sh

	# Make sure the right artifacts are going to be built
	make clean

	check_daemon_setup

	info "containerd(cri): testing using runtime: ${containerd_runtime_test}"

	create_containerd_config "${containerd_runtime_test}"

	info "containerd(cri): Running cri-tools"
	sudo -E PATH="${PATH}:/usr/local/bin" \
		FOCUS="runtime should support basic operations on container" \
		RUNTIME="" \
		SKIP="runtime should support execSync with timeout" \
		REPORT_DIR="${REPORT_DIR}" \
		CONTAINERD_CONFIG_FILE="$CONTAINERD_CONFIG_FILE" \
		make -e test-cri

	info "containerd(cri): Running test-integration"

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

	create_containerd_config "${containerd_runtime_test}"

	for t in "${passing_test[@]}"
	do
		sudo -E PATH="${PATH}:/usr/local/bin" \
			REPORT_DIR="${REPORT_DIR}" \
			FOCUS="${t}" \
			RUNTIME="" \
			CONTAINERD_CONFIG_FILE="$CONTAINERD_CONFIG_FILE" \
			make -e test-integration
	done

	TestContainerMemoryUpdate 1
	TestContainerMemoryUpdate 0

	TestKilledVmmCleanup

	popd
}

main
