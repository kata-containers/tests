#!/bin/bash
#
# Copyright (c) 2021 Intel Corporation
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

declare -r container_id="vfiotest${RANDOM}"

tmp_data_dir="$(mktemp -d)"
trap cleanup EXIT

# kata-runtime options
SANDBOX_CGROUP_ONLY=""
HYPERVISOR=
MACHINE_TYPE=
IMAGE_TYPE=

cleanup() {
	sudo ctr t kill -a -s 9 $(sudo ctr task list -q) && sleep 3
	sudo ctr t rm -f $(sudo ctr task list -q) && sleep 3
	sudo ctr c rm $(sudo ctr c list -q)
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
	image="quay.io/prometheus/busybox:latest"
	sudo -E ctr i pull ${image}
	sudo -E ctr i export "${rootfs_tar}" "${image}"
	sudo chown ${USER}:${USER} "${rootfs_tar}"
	sync

	# extract busybox rootfs
	rootfs_dir="${bundle_dir}/rootfs"
	mkdir -p "${rootfs_dir}"
	layers_dir="$(mktemp -d)"
	tar -C "${layers_dir}" -pxf "${rootfs_tar}"
	for ((i=0;i<$(cat ${layers_dir}/manifest.json | jq -r ".[].Layers | length");i++)); do
		tar -C ${rootfs_dir} -xf ${layers_dir}/$(cat ${layers_dir}/manifest.json | jq -r ".[].Layers[${i}]")
	done
	sync

	# Copy config.json
	cp -a "${script_path}/config.json" "${bundle_dir}/config.json"
}

run_container() {
	bundle_dir="$1"
	sudo -E ctr run -d --runtime io.containerd.run.kata.v2 --config "${bundle_dir}/config.json" "${container_id}"
}

check_eth_dev() {
	# container MUST have a eth net interface
	sudo -E ctr t exec --exec-id 2 "${container_id}" ip a | grep "eth"
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

	# machine type applies to configuration.toml and configuration-qemu.toml
	if [ -n "$MACHINE_TYPE" ]; then
		if [ "$HYPERVISOR" = "qemu" ]; then
			sed -i 's|^machine_type.*|machine_type = "'${MACHINE_TYPE}'"|g' "${kata_config_file}"
		else
			warn "Variable machine_type only applies to qemu. It will be ignored"
		fi
	fi

	if [ -n "${SANDBOX_CGROUP_ONLY}" ]; then
	   sed -i 's|^sandbox_cgroup_only.*|sandbox_cgroup_only='${SANDBOX_CGROUP_ONLY}'|g' "${kata_config_file}"
	fi

	# Change to initrd or image depending on user input.
	# Non-default configs must be changed to specify either initrd or image, image is default.
	if [ "$IMAGE_TYPE" = "initrd" ]; then
		if $(grep -q "^image.*" ${kata_config_file}); then
			if $(grep -q "^initrd.*" ${kata_config_file}); then
				sed -i '/^image.*/d' "${kata_config_file}"
			else
				sed -i 's|^image.*|initrd = "'${initrd_file}'"|g' "${kata_config_file}"
			fi
		fi
	else
		if $(grep -q "^initrd.*" ${kata_config_file}); then
			if $(grep -q "^image.*" ${kata_config_file}); then
				sed -i '/^initrd.*/d' "${kata_config_file}"
			else
				sed -i 's|^initrd.*|image = "'${image_file}'"|g' "${kata_config_file}"
			fi
		fi
	fi

	# enable debug
	sed -i -e 's/^#\(enable_debug\).*=.*$/\1 = true/g' \
	       -e 's/^kernel_params = "\(.*\)"/kernel_params = "\1 agent.log=debug"/g' \
	       "${kata_config_file}"
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

	restart_containerd_service
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

	# create container bundle
	bundle_dir="${tmp_data_dir}/bundle"

	# generate final config.json
	config_json_in="${script_path}/config.json.in"
	sed -e '/^#.*/d' \
		-e 's|@VFIO_PATH@|'"${vfio_device}"'|g' \
		-e 's|@VFIO_MAJOR@|'"${vfio_major}"'|g' \
		-e 's|@VFIO_MINOR@|'"${vfio_minor}"'|g' \
		-e 's|@ROOTFS@|'"${bundle_dir}/rootfs"'|g' \
		"${config_json_in}" > "${script_path}/config.json"

	create_bundle "${bundle_dir}"

	# run container
	run_container "${bundle_dir}"

	# run container checks
	check_eth_dev
}

main $@
