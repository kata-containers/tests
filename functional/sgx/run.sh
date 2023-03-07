#!/bin/bash
#
# Copyright (c) 2022 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -x
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

script_path=$(dirname "$0")
source "${script_path}/../../lib/common.bash"

tmp_data_dir="$(mktemp -d)"
rootfs_tar="${tmp_data_dir}/rootfs.tar"
trap cleanup EXIT

# kata-runtime options
HYPERVISOR=${HYPERVISOR:-"qemu"}

cleanup() {
	clean_env_ctr
	sudo rm -rf "${tmp_data_dir}"
}

pull_rootfs() {
	# pull and export busybox image in tar file
	local image="quay.io/prometheus/busybox:latest"
	sudo -E ctr i pull ${image}
	sudo -E ctr i export "${rootfs_tar}" "${image}"
	sudo chown ${USER}:${USER} "${rootfs_tar}"
	sync
}

create_bundle() {
	local bundle_dir="$1"
	mkdir -p "${bundle_dir}"

	# extract busybox rootfs
	local rootfs_dir="${bundle_dir}/rootfs"
	mkdir -p "${rootfs_dir}"
	local layers_dir="$(mktemp -d)"
	tar -C "${layers_dir}" -pxf "${rootfs_tar}"
	for ((i=0;i<$(cat ${layers_dir}/manifest.json | jq -r ".[].Layers | length");i++)); do
		tar -C ${rootfs_dir} -xf ${layers_dir}/$(cat ${layers_dir}/manifest.json | jq -r ".[].Layers[${i}]")
	done
	sync

	# Copy config.json
	cp -a "${script_path}/config.json" "${bundle_dir}/config.json"
}

run_container() {
	local container_id="$1"
	local bundle_dir="$2"

	sudo -E ctr run -d --runtime io.containerd.kata.v2 --config "${bundle_dir}/config.json" "${container_id}"
}

get_ctr_cmd_output() {
	local container_id="$1"
	shift
	sudo -E ctr t exec --exec-id 2 "${container_id}" "${@}"
}

get_dmesg() {
	local container_id="$1"
	get_ctr_cmd_output "${container_id}" dmesg
}

setup_configuration_file() {
	local qemu_config_file="configuration-qemu.toml"
	local clh_config_file="configuration-clh.toml"
	local kata_config_file=""

	for file in $(kata-runtime --kata-show-default-config-paths); do
		if [ ! -f "${file}" ]; then
			continue
		fi

		kata_config_file="${file}"
		config_dir=$(dirname ${file})
		config_filename=""

		if [ "$HYPERVISOR" = "qemu" ]; then
			config_filename="${qemu_config_file}"
		elif [ "$HYPERVISOR" = "clh" ]; then
			config_filename="${clh_config_file}"
		fi

		config_file="${config_dir}/${config_filename}"
		if [ -f "${config_file}" ]; then
			rm -f "${kata_config_file}"
			cp -a $(realpath "${config_file}") "${kata_config_file}"
			break
		fi
	done

	# enable debug
	sed --follow-symlinks -i -e 's/^#\(enable_debug\).*=.*$/\1 = true/g' \
	       -e 's/^#\(debug_console_enabled\).*=.*$/\1 = true/g' \
	       -e 's/^kernel_params = "\(.*\)"/kernel_params = "\1 agent.log=debug"/g' \
	       "${kata_config_file}"
}

run_test_container() {
	local container_id="$1"
	local bundle_dir="$2"
	local config_json_in="$3"

	# generate final config.json
	sed -e '/^#.*/d' \
	    -e 's|@ROOTFS@|'"${bundle_dir}/rootfs"'|g' \
	    "${config_json_in}" > "${script_path}/config.json"

	create_bundle "${bundle_dir}"

	# run container
	run_container "${container_id}" "${bundle_dir}"

	get_ctr_cmd_output "${container_id}" grep -qio sgx /proc/cpuinfo
	get_dmesg "${container_id}" | grep -qio "sgx: EPC section"

	# output VM dmesg
	get_dmesg "${container_id}"
}

main() {
	#
	# Get the device ready on the host
	#
	setup_configuration_file

	restart_containerd_service

	# Get the rootfs we'll use for all tests
	pull_rootfs

	#
	# Run the tests
	#
	# test sgx
	sgx_cid="sgx-${RANDOM}"
	run_test_container "${sgx_cid}" \
			   "${tmp_data_dir}/sgx" \
			   "${script_path}/sgx.json.in"
}

main $@
