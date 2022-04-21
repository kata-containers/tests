#!/bin/bash
#
# Copyright (c) 2022 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

script_path=$(dirname "$0")
source "${script_path}/../../../lib/common.bash"
tdx_tmp_dir=$(mktemp -d)
container_qmp_socket="${tdx_tmp_dir}/qmp.sock"
qemu_tdx_wrapper_path="${tdx_tmp_dir}/qemu-tdx.sh"
config_file=""
jenkins_job_url="http://jenkins.katacontainers.io/job"
FIRMWARE="${FIRMWARE:-}"
FIRMWARE_VOLUME="${FIRMWARE_VOLUME:-}"
KATA_HYPERVISOR="${KATA_HYPERVISOR:-qemu}"
kernel_tdx_path="/usr/share/kata-containers/vmlinuz-tdx.container"
qemu_tdx_path="/usr/local/bin/qemu-system-x86_64"

trap remove_tdx_tmp_dir EXIT

setup_tdx() {
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

remove_tdx_tmp_dir() {
	sudo rm -rf ${tdx_tmp_dir}
}
