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
source "${script_path}/lib/common-tdx.bash"

tmp_dir=$(mktemp -d)
guest_memory_path="${tmp_dir}/guest_mem"
runtime_type="io.containerd.kata.v2"
config_file=""
container_name=test
KATA_HYPERVISOR="${KATA_HYPERVISOR:-qemu}"

trap cleanup EXIT

cleanup() {
	local config_file="$(get_config_file)"
	sudo mv -f "${config_file}.bak" "${config_file}"

	sudo ctr t kill -s 15 ${container_name} || true
	sudo ctr t rm -f ${container_name} || true
	sudo ctr c rm ${container_name} || true

	clean_env_ctr

	sudo rm -rf ${tmp_dir}
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
	get_config_file
	setup_tdx
	install_qemu_tdx
	install_kernel_tdx
	enable_confidential_computing

	run_test
	remove_tdx_tmp_dir
}

main $@
