#!/bin/bash
#
# Copyright (c) 2017-2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

[ -z "${DEBUG:-}" ] || set -x

readonly script_name="$(basename "${BASH_SOURCE[0]}")"

cidir=$(dirname "$0")
source "${cidir}/lib.sh"

build_and_install_kernel() {
	local kernel_type=${1:-}

	[ -n "${kernel_type}" ] || die "kernel type is empty"

	info "Installing '${kernel_type}' kernel"

	build_static_artifact_and_install "$kernel_type"
}

die_unsupported_kernel_type() {
	local kernel_type="${1:-}"

	info "kernel type '${kernel_type}' not supported"
	usage 1
}

usage() {
	exit_code="$1"
	cat <<EOF
Overview:

	Build and install a kernel for Kata Containers

Usage:

	$script_name [options]

Options:
    -d          : Enable bash debug.
    -h          : Display this help.
    -t <kernel> : kernel type, such as vanilla, experimental, dragonball, etc
EOF
	exit "$exit_code"
}

main() {
	local kernel_type="vanilla"

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
				kernel_type="${OPTARG}"
				;;
		esac
	done

	clone_katacontainers_repo

	case "${kernel_type}" in
		experimental)
			build_and_install_kernel "kernel-experimental"
			;;
		arm-experimental)
			build_and_install_kernel "kernel-arm-experimental"
			;;
		vanilla)
			build_and_install_kernel "kernel"
			;;
		dragonball)
			build_and_install_kernel "kernel-dragonball-experimental"
			;;
		*)
			die_unsupported_kernel_type "$kernel_type"
			;;
	esac
}

main $@
