#!/bin/bash
#
# Copyright (c) 2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

readonly script_name="$(basename "${BASH_SOURCE[0]}")"
cidir=$(dirname "$0")
source "${cidir}/lib.sh"
source "${cidir}/../lib/common.bash"
source /etc/os-release || source /usr/lib/os-release

usage() {
	exit_code="$1"
	cat <<EOF
Overview:

	Build and install QEMU for Kata Containers

Usage:

	$script_name [options]

Options:
    -d          : Enable bash debug.
    -h          : Display this help.
    -t <qemu> : qemu type, such as tdx, vanilla.
EOF
	exit "$exit_code"
}

main() {
	local qemu_type="vanilla"

	while getopts "dht:" opt; do
		case "$opt" in
			d)
				PS4=' Line ${LINENO}: '
				set -x
				;;
			h)
				usage 0
				;;
			t)
				qemu_type="${OPTARG}"
				;;
		esac
	done

	export qemu_type
	case "${qemu_type}" in
		vanilla)
			qemu_type="qemu"
			;;
		*)
			die_unsupported_qemu_type "$qemu_type"
			;;
	esac

	build_static_artifact_and_install "${qemu_type}"
}

main $@
