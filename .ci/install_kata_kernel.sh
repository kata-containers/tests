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

KATA_BUILD_CC="${KATA_BUILD_CC:-no}"

build_and_install_kernel() {
	local kernel_type=${1:-}

	[ -n "${kernel_type}" ] || die "kernel type is empty"
	
	info "Installing '${kernel_type}' kernel"

	build_static_artifact_and_install "$kernel_type"
}

build_and_install_kernel_for_cc() {
	local kernel_type="${1:-}"
	local artifact="kernel"

	case "$kernel_type" in
		tdx)
			artifact="${artifact}-tdx-experimental"
			;;
		sev|snp)
			artifact="${artifact}-sev"
			;;
		vanilla) ;;
		*)
			die_unsupported_kernel_type "$kernel_type"
			;;
	esac

	build_static_artifact_and_install "${artifact}"
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
    -t <kernel> : kernel type, such as vanilla, experimental, dragonball, tdx, sev, snp.
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

	if [ "$KATA_BUILD_CC" == "yes" ]; then
		build_and_install_kernel_for_cc "$kernel_type"
		return
	fi

	case "${kernel_type}" in
		experimental)
			build_and_install_kernel "kernel-experimental"
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
