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

# kata-runtime options
SANDBOX_CGROUP_ONLY=""
HYPERVISOR=
MACHINE_TYPE=
IMAGE_TYPE=

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
        -h,          Help
        -i <string>, Specify initrd or image
        -m <string>, Specify kata-runtime machine type for qemu hypervisor
        -p <string>, Specify kata-runtime hypervisor
        -s <value>,  Set sandbox_cgroup_only in the configuration file
EOF
}

setup_configuration_file() {
	local qemu_config_file="configuration-qemu.toml"
	local clh_config_file="configuration-clh.toml"
	local image_file="/usr/share/kata-containers/kata-containers.img"
	local initrd_file="/usr/share/kata-containers/kata-containers-initrd.img"

	for file in $(kata-runtime --kata-show-default-config-paths); do
		config_dir=$(dirname ${file})
		config_filename=$(basename ${file})

		if [ "$HYPERVISOR" = "qemu" ]; then
			config_filename="${qemu_config_file}"
		elif [ "$HYPERVISOR" = "clh" ]; then
			config_filename="${clh_config_file}"
		fi

		config_file="${config_dir}/${config_filename}"

		if [ -f "${config_file}" ]; then
			cp -a "${config_file}" "${CONFIG_FILE}"
			break
		elif [ -f ${file} ]; then
			cp -a ${file} "${CONFIG_FILE}"
			break
		fi
	done

	# machine type applies to configuration.toml and configuration-qemu.toml
	if [ -n "$MACHINE_TYPE" ]; then
		if [ "$HYPERVISOR" = "qemu" ]; then
			sed -i 's|^machine_type.*|machine_type = "'${MACHINE_TYPE}'"|g' "${CONFIG_FILE}"
		else
			warn "Variable machine_type only applies to qemu. It will be ignored"
		fi
	fi

	if [ -n "${SANDBOX_CGROUP_ONLY}" ]; then
	   sed -i 's|^sandbox_cgroup_only.*|sandbox_cgroup_only='${SANDBOX_CGROUP_ONLY}'|g' "${CONFIG_FILE}"
	fi

	# Change to initrd or image depending on user input.
	# Non-default configs must be changed to specify either initrd or image, image is default.
	if [ "$IMAGE_TYPE" = "initrd" ]; then
		if $(grep -q "^image.*" $CONFIG_FILE); then
			if $(grep -q "^initrd.*" $CONFIG_FILE); then
				sed -i '/^image.*/d' "${CONFIG_FILE}"
			else
				sed -i 's|^image.*|initrd = "'${initrd_file}'"|g' "${CONFIG_FILE}"
			fi
		fi
	else
		if $(grep -q "^initrd.*" $CONFIG_FILE); then
			if $(grep -q "^image.*" $CONFIG_FILE); then
				sed -i '/^initrd.*/d' "${CONFIG_FILE}"
			else
				sed -i 's|^initrd.*|image = "'${image_file}'"|g' "${CONFIG_FILE}"
			fi
		fi
	fi

	# enable debug
	sed -i -e 's/^#\(enable_debug\).*=.*$/\1 = true/g' \
	       -e 's/^kernel_params = "\(.*\)"/kernel_params = "\1 agent.log=debug"/g' \
	       "${CONFIG_FILE}"
}

main() {
	local OPTIND
	while getopts "hi:m:p:s:" opt;do
		case ${opt} in
		h)
		    help
		    exit 0;
		    ;;
		i)
		    IMAGE_TYPE="${OPTARG}"
		    ;;
		m)
		    MACHINE_TYPE="${OPTARG}"
		    ;;
		p)
		    HYPERVISOR="${OPTARG}"
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
