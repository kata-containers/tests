#!/bin/bash
#
# Copyright (c) 2021 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

FILE=""
FS=""
MNT_DIR=""
SIZE=""

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/../../lib/common.bash"

help() {
cat << EOF
$0 is a command line tool to create raw files that can be used as pmem
volumes that support DAX[1] in Kata Containers.

USAGE:
	$0 [OPTIONS] FILE

EXAMPLE:
	$0 -s 10G -f xfs -m ~/dax_volume ~/file.dax

OPTIONS:
	-f FS   filesystem, only xfs(5) and ext4(5) support DAX[1]
	-m DIR  mount point in the host. Create a loop device for the file
	        and mount it in the DIR specified, DIR can be used as a volume
	        and Kata Containers will use it as a pmem volume that support DAX
	-s SIZE file size. SIZE must be aligned to 128M, hence the minimum
	        supported size for a file is 128M

	[1]- https://www.kernel.org/doc/Documentation/filesystems/dax.txt
EOF
}

create_file() {
	local reserved_blocks_percentage=3
	local block_size=4096
	local data_offset=$((1024*1024*2))
	local dax_alignment=$((1024*1024*2))
	local nsdax_src_url="https://raw.githubusercontent.com/kata-containers/kata-containers/main/tools/osbuilder/image-builder/nsdax.gpl.c"

	truncate -s "${SIZE}" "${FILE}"
	if [ $((($(stat -c '%s' "${FILE}")/1024/1024)%128)) -ne 0 ]; then
		rm -f "${FILE}"
		die "SIZE must be aligned to 128M"
	fi

	if [ ! -x nsdax ]; then
		curl -Ls "${nsdax_src_url}" | gcc -x c -o nsdax -
	fi
	./nsdax "${FILE}" ${data_offset} ${dax_alignment}
	sync

	device=$(sudo losetup --show -Pf --offset ${data_offset} "${FILE}")
	if [ "${FS}" == "xfs" ]; then
		# DAX and reflink cannot be used together!
		# Explicitly disable reflink, if reflink is listed in the metadata (-m) option
		if mkfs.xfs 2>&1 | grep "\-m" | grep "reflink"; then
			sudo mkfs.xfs -m reflink=0 -q -f -b size="${block_size}" "${device}"
		else
			sudo mkfs.xfs -q -f -b size="${block_size}" "${device}"
		fi
	else
		sudo mkfs.ext4 -q -F -b "${block_size}" "${device}"
		info "Set filesystem reserved blocks percentage to ${reserved_blocks_percentage}%"
		sudo tune2fs -m "${reserved_blocks_percentage}" "${device}"
	fi

	if [ -z "${MNT_DIR}" ]; then
		info "pmem volume will not be mounted"
		info "It can be mounted later running: sudo mount \$(sudo losetup --show -Pf --offset ${data_offset} ${FILE}) \$MNT_DIR"
		sudo losetup -d "${device}"
	else
		info "Mounting pmem volume at ${MNT_DIR}"
		sudo mount "${device}" "${MNT_DIR}"
	fi
}

main() {
	local OPTIND
	while getopts "f:hm:s:" opt;do
		case ${opt} in
			f)
				FS="${OPTARG}"
				;;
			h)
				help
				exit 0
				;;
			m)
				MNT_DIR="${OPTARG}"
				;;
			s)
				SIZE="${OPTARG}"
				;;
			?)
				# parse failure
				help
				die "Failed to parse arguments"
		    ;;
		esac
	done
	shift $((OPTIND-1))

	FILE=$1

	if [ -z "${FILE}" ]; then
		die "mandatory FILE not supplied"
	fi

	if [ -z "${FS}" ]; then
		FS="xfs"
		warn "filesystem not supplied, using ${FS}"
	elif [ "${FS}" != "xfs" ] &&  [ "${FS}" != "ext4" ]; then
		die "Unsupported filesystem ${FS}"
	fi

	if [ -z "${SIZE}" ]; then
		SIZE="128M"
		warn "size not supplied, using ${SIZE}"
	fi

	create_file
}

main $@
