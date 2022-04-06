#!/bin/bash
#
# Copyright (c) 2022 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

[ -z "${DEBUG:-}" ] || set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

script_path=$(dirname "$0")
source "${script_path}/../../lib/common.bash"

tmp_dir=$(mktemp -d)
container_qmp_socket="${tmp_dir}/qmp.sock"
qemu_tdx_wrapper_path="${tmp_dir}/qemu-tdx.sh"
guest_memory_path="${tmp_dir}/guest_mem"
runtime_type="io.containerd.kata.v2"
config_file=""
kernel_tdx_path="/usr/share/kata-containers/vmlinuz-tdx.container"
qemu_tdx_path="/usr/local/bin/qemu-system-x86_64"
container_name=test
jenkins_job_url="http://jenkins.katacontainers.io/job"
FIRMWARE="${FIRMWARE:-}"
FIRMWARE_VOLUME="${FIRMWARE_VOLUME:-}"
KATA_HYPERVISOR="${KATA_HYPERVISOR:-qemu}"

trap cleanup EXIT

setup() {
	[ "$(uname -m)" == "x86_64" ] || die "Only x86_64 is supported"
	[ -d "/sys/firmware/tdx_seam" ] || die "Intel TDX is not available in this system"

	[ -n "${FIRMWARE}" ] || die "FIRMWARE environment variable is not set"
	[ -n "${FIRMWARE_VOLUME}" ] || warn "FIRMWARE_VOLUME environment variable is not set"

	[ "${KATA_HYPERVISOR}" == "qemu" ] || die "This test only supports QEMU for now"

	local config_file="$(get_config_file)"
	sudo cp "${config_file}" "${config_file}.bak"

	# we need other qmp socket because the default socket is used by kata-shim
	cat > ${qemu_tdx_wrapper_path} <<EOF
#!/bin/bash
${qemu_tdx_path} -qmp unix:${container_qmp_socket},server=on,wait=off "\$@"
EOF
	chmod +x ${qemu_tdx_wrapper_path}
}

get_config_file() {
	if [ -z "${config_file}" ]; then
		for f in $(kata-runtime --show-default-config-paths); do
			[ -f "${f}" ] && config_file="${f}" && break
		done
	fi
	echo "${config_file}"
}

cleanup() {
	local config_file="$(get_config_file)"
	sudo mv -f "${config_file}.bak" "${config_file}"

	sudo ctr t kill -s 15 ${container_name} || true
	sudo ctr t rm -f ${container_name} || true
	sudo ctr c rm ${container_name} || true

	clean_env_ctr

	sudo rm -rf ${tmp_dir}
}

enable_confidential_computing() {
	local conf_file="$(get_config_file)"
	[ -n "${conf_file}" ] || die "configuration file not found"
	sudo crudini --set "${conf_file}" 'hypervisor.qemu' 'path' '"'${qemu_tdx_wrapper_path}'"'
	sudo crudini --set "${conf_file}" 'hypervisor.qemu' 'kernel' '"'${kernel_tdx_path}'"'
	sudo crudini --set "${conf_file}" 'hypervisor.qemu' 'kernel_params' '"force_tdx_guest tdx_disable_filter"'
	sudo crudini --set "${conf_file}" 'hypervisor.qemu' 'firmware' '"'${FIRMWARE}'"'
	sudo crudini --set "${conf_file}" 'hypervisor.qemu' 'firmware_volume' '"'${FIRMWARE_VOLUME}'"'
	sudo crudini --set "${conf_file}" 'hypervisor.qemu' 'cpu_features' '"pmu=off,-kvm-steal-time"'
	sudo sed -i 's|^# confidential_guest.*|confidential_guest = true|' "${conf_file}"
}

install_kernel_tdx() {
	local kernel_url="${jenkins_job_url}/kata-containers-2.0-kernel-tdx-x86_64-nightly/lastSuccessfulBuild/artifact/artifacts"
	local latest=$(curl ${kernel_url}/latest)
	curl -L ${kernel_url}/vmlinuz-${latest} -o vmlinuz-tdx.container
	sudo mv -f vmlinuz-tdx.container ${kernel_tdx_path}
}

install_qemu_tdx() {
	local qemu_url="${jenkins_job_url}/kata-containers-2.0-qemu-tdx-x86_64/lastSuccessfulBuild/artifact/artifacts/kata-static-qemu.tar.gz"
	curl "${qemu_url}" | sudo tar --strip-components=1 -C /usr/local/ -zxf -
}

run_test() {
	local eid=0
	local secret_data=verysecretdata
	sudo -E ctr i pull mirror.gcr.io/library/ubuntu:latest
	sudo -E ctr run -d --runtime ${runtime_type} mirror.gcr.io/library/ubuntu:latest ${container_name} \
		 sh -c "export d=${secret_data}; tail -f /dev/null"
	waitForProcess 30 5 "sudo ctr t exec --exec-id $((eid+=1)) ${container_name} true"
	sudo ctr t exec --exec-id $((eid+=1)) ${container_name} sh -c 'dmesg | grep -qio "tdx: guest initialized"'
	sudo ctr t exec --exec-id $((eid+=1)) ${container_name} grep -qio "tdx_guest" /proc/cpuinfo

	# dump guest memory and look for secret data, it *must not* be visible
	echo '{"execute":"qmp_capabilities"}{"execute":"dump-guest-memory","arguments":{"paging":false,"protocol":"file:'${guest_memory_path}'"}}'| \
		sudo socat - unix-connect:"${container_qmp_socket}"
	sudo fgrep -v ${secret_data} ${guest_memory_path} || die "very secret data is visible in guest memory!"
}

main() {
	setup
	install_qemu_tdx
	install_kernel_tdx
	enable_confidential_computing

	run_test
}

main $@
