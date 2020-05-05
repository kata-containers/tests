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

cleanup() {
	sudo kata-runtime kill "${container_id}"
	sudo kata-runtime delete -f "${container_id}"

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

	sudo kata-runtime run --detach -b "${bundle_dir}" --pid-file="${tmp_data_dir}/pid" "${container_id}"
}

check_eth_dev() {
	# container MUST have a eth net interface
	sudo kata-runtime exec "${container_id}" ip a | grep "eth"
}

main() {
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
