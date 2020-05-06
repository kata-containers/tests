#!/bin/bash
#
# Copyright (c) 2020 Intel Corporation
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

declare -r container_id="vfiotest"

tmp_data_dir="$(mktemp -d)"
trap cleanup EXIT

CONFIG_FILE="${tmp_data_dir}/configuration.toml"
SANDBOX_CGROUP_ONLY=""

cleanup() {
	sudo kata-runtime --kata-config "${CONFIG_FILE}" kill "${container_id}" || true
	sudo kata-runtime --kata-config "${CONFIG_FILE}" delete -f "${container_id}" || true
	sudo rm -rf "${tmp_data_dir}"
}

get_eth_addr() {
	lspci | grep "Ethernet controller" | grep "Virtio network device" | tail -1 | cut -d' ' -f1
}

unbind_pci_dev() {
	addr="$1"
	echo "0000:${addr}" | sudo tee "/sys/bus/pci/devices/0000:${addr}/driver/unbind"
}

get_pci_dev_vendor_id() {
	addr="$1"
	lspci -n -s "${addr}" | cut -d' ' -f3 | sed 's|:| |'
}

bind_to_vfio() {
	dev_vendor_id="$1"
	echo "${dev_vendor_id}" | sudo tee "/sys/bus/pci/drivers/vfio-pci/new_id"
}

get_vfio_path() {
	addr="$1"
	echo "/dev/vfio/$(basename $(realpath /sys/bus/pci/drivers/vfio-pci/0000:${addr}/iommu_group))"
}

create_bundle() {
	bundle_dir="$1"
	mkdir -p "${bundle_dir}"

	# pull and export busybox image in tar file
	rootfs_tar="${tmp_data_dir}/rootfs.tar"
	sudo docker pull busybox
	cont_id=$(sudo docker create busybox)
	sudo docker export -o "${rootfs_tar}" "${cont_id}"
	sudo chown ${USER}:${USER} "${rootfs_tar}"
	sync
	sudo docker rm -f "${cont_id}"

	# extract busybox rootfs
	rootfs_dir="${bundle_dir}/rootfs"
	mkdir -p "${rootfs_dir}"
	tar -C "${rootfs_dir}" -pxf "${rootfs_tar}"
	sync

	# Copy config.json
	cp -a "${script_path}/config.json" "${bundle_dir}/config.json"
}

run_container() {
	bundle_dir="$1"

	sudo kata-runtime --kata-config "${CONFIG_FILE}" run --detach \
		 -b "${bundle_dir}" --pid-file="${tmp_data_dir}/pid" "${container_id}"
}

check_eth_dev() {
	# container MUST have a eth net interface
	sudo kata-runtime --kata-config "${CONFIG_FILE}" exec "${container_id}" ip a | grep "eth"
}

# Show help about this script
help(){
cat << EOF
Usage: $0 [-h] [options]
    Description:
        This script runs a kata container and passthrough a vfio device
    Options:
        -h,         Help
        -s <value>, Set sandbox_cgroup_only in the configuration file
EOF
}

setup_configuration_file() {
	for file in $(kata-runtime --kata-show-default-config-paths); do
		if [ -f "${file}" ]; then
			cp -a "${file}" "${CONFIG_FILE}"
			break
		fi
	done

	if [ -n "${SANDBOX_CGROUP_ONLY}" ]; then
	   sed -i 's|^sandbox_cgroup_only.*|sandbox_cgroup_only='${SANDBOX_CGROUP_ONLY}'|g' "${CONFIG_FILE}"
	fi
}

main() {
	local OPTIND
	while getopts "hs:" opt;do
		case ${opt} in
		h)
		    help
		    exit 0;
		    ;;
		s)
		    SANDBOX_CGROUP_ONLY="${OPTARG}"
		    ;;
		?)
		    # parse failure
		    help
		    die "Failed to parse arguments"
		    ;;
		esac
	done
	shift $((OPTIND-1))

	setup_configuration_file

	sudo modprobe vfio
	sudo modprobe vfio-pci

	addr=$(get_eth_addr)
	[ -n "${addr}" ] || die "virtio ethernet controller address not found"

	unbind_pci_dev "${addr}"

	dev_vendor_id="$(get_pci_dev_vendor_id "${addr}")"
	bind_to_vfio "${dev_vendor_id}"

	# get vfio information
	vfio_device="$(get_vfio_path "${addr}")"
	[ -n "${vfio_device}" ] || die "vfio device not found"
	vfio_major="$(printf '%d' $(stat -c '0x%t' ${vfio_device}))"
	vfio_minor="$(printf '%d' $(stat -c '0x%T' ${vfio_device}))"

	# generate final config.json
	config_json_in="${script_path}/config.json.in"
	sed -e '/^#.*/d' \
		-e 's|@VFIO_PATH@|'"${vfio_device}"'|g' \
		-e 's|@VFIO_MAJOR@|'"${vfio_major}"'|g' \
		-e 's|@VFIO_MINOR@|'"${vfio_minor}"'|g' \
		"${config_json_in}" > "${script_path}/config.json"

	# create container bundle
	bundle_dir="${tmp_data_dir}/bundle"
	create_bundle "${bundle_dir}"

	# run container
	run_container "${bundle_dir}"

	# run container checks
	check_eth_dev
}

main $@
