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

PREFIX=${PREFIX:-/opt/kata}
CURRENT_QEMU_VERSION=""
QEMU_REPO_URL=""
QEMU_ARCH=$(${cidir}/kata-arch.sh -d)

# option "--shallow-submodules" was introduced in git v2.9.0
GIT_SHADOW_VERSION="2.9.0"

# Build QEMU for Confidential Containers.
build_and_install_qemu_for_cc() {
	local artifact="qemu"

	case "${qemu_type}" in
		tdx)
			artifact="${qemu_type}-${artifact}"
			;;
		vanilla) ;;
		*)
			die_unsupported_qemu_type "$qemu_type"
			;;
	esac

	build_static_artifact_and_install "$artifact"
}

# This is used by the arch specific files
clone_qemu_repo() {
	# check if git is capable of shadow cloning
	git_shadow_clone=$(check_git_version "${GIT_SHADOW_VERSION}")

	if [ "$git_shadow_clone" == "true" ]; then
		sudo -E git clone --branch "${CURRENT_QEMU_VERSION}" --single-branch --depth 1 --shallow-submodules "${QEMU_REPO_URL}" "${GOPATH}/src/${gopath_qemu_repo}"
	else
		sudo -E git clone --branch "${CURRENT_QEMU_VERSION}" --single-branch --depth 1 "${QEMU_REPO_URL}" "${GOPATH}/src/${gopath_qemu_repo}"
	fi
}

#Load specific configure file
if [ -f "${cidir}/${QEMU_ARCH}/lib_install_qemu_${QEMU_ARCH}.sh" ]; then
       source "${cidir}/${QEMU_ARCH}/lib_install_qemu_${QEMU_ARCH}.sh"
fi

die_unsupported_qemu_type() {
	local qemu_type="${1:-}"

	info "qemu type '${qemu_type}' not supported"
	usage 1
}

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

	if [ "${KATA_BUILD_CC}" == "yes" ]; then
		build_and_install_qemu_for_cc
	fi

	export qemu_type
	case "${qemu_type}" in
		vanilla)
			qemu_type="qemu"
			;;
		*)
			die_unsupported_qemu_type "$qemu_type"
			;;
	esac

	case ${QEMU_ARCH} in
		"aarch64"|"ppc64le")
			# We're still no there for using the kata-deploy
			# scripts with ppc64le and aarch64.
			CURRENT_QEMU_VERSION=$(get_version "assets.hypervisor.qemu.version")
			QEMU_REPO_URL=$(get_version "assets.hypervisor.qemu.url")

			# Strip "https://" to clone into $GOPATH
			gopath_qemu_repo=${QEMU_REPO_URL/https:\/\//}
			# These variables are used by static-build scripts
			export qemu_version="${CURRENT_QEMU_VERSION}"
			export qemu_repo="${QEMU_REPO_URL}"

			build_and_install_qemu
			;;
		"x86_64"|"s390x")
			build_static_artifact_and_install "${qemu_type}"
			;;
		*)
			die "Architecture ${QEMU_ARCH} not supported"
			;;
	esac
}

main $@