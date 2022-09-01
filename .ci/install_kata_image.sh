#!/bin/bash
#
# Copyright (c) 2019-2020 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

cidir=$(dirname "$0")
source "${cidir}/lib.sh"
rust_agent_repo=${katacontainers_repo:="github.com/kata-containers/kata-containers"}
arch=$("${cidir}"/kata-arch.sh -d)
go_arch=$("${cidir}"/kata-arch.sh -g)
PREFIX="${PREFIX:-/usr}"
DESTDIR="${DESTDIR:-/}"
image_path="${DESTDIR}${image_path:-${PREFIX}/share/kata-containers}"
image_name="${image_name:-kata-containers.img}"
initrd_name="${initrd_name:-kata-containers-initrd.img}"
AGENT_INIT="${AGENT_INIT:-${TEST_INITRD:-no}}"
TEST_INITRD="${TEST_INITRD:-no}"
build_method="${BUILD_METHOD:-distro}"
EXTRA_PKGS="${EXTRA_PKGS:-}"

build_rust_image() {
	osbuilder_path="${GOPATH}/src/${rust_agent_repo}/tools/osbuilder"

	sudo mkdir -p "${image_path}"

	pushd "${osbuilder_path}"
	target_image="image"
	file_to_install="${osbuilder_path}/${image_name}"
	if [ "${TEST_INITRD}" == "yes" ]; then
		if [ "${AGENT_INIT}" != "yes" ]; then
			die "TEST_INITRD=yes without AGENT_INIT=yes is unsupported"
		fi
		target_image="initrd"
		file_to_install="${osbuilder_path}/${initrd_name}"
	fi
	info "Building ${target_image} with AGENT_INIT=${AGENT_INIT}"
	case "$build_method" in
		"distro")
			if [[ ! "${osbuild_docker:-}" =~ ^(0|false|no)$ ]]; then
				use_docker="${osbuild_docker:-}"
				[[ -z "${USE_PODMAN:-}" ]] && use_docker="${use_docker:-1}"
			fi
			distro="${osbuilder_distro:-ubuntu}"
			if [ ${KATA_BUILD_CC} == "yes" ]; then
				sudo -E USE_DOCKER="${use_docker:-}" DISTRO="${distro}" AA_KBC="${AA_KBC:-}" UMOCI=yes make -e "image"
			else
				sudo -E USE_DOCKER="${use_docker:-}" DISTRO="${distro}" EXTRA_PKGS="${EXTRA_PKGS}" \
					make -e "${target_image}"
			fi
			;;
		"dracut")
			sudo -E BUILD_METHOD="dracut" make -e "${target_image}"
			;;
		*)
			die "Unknown build method ${build_method}"
			;;
	esac
	info "Install ${target_image} to ${image_path}"
	local file="$(realpath ${image_path}/$(basename ${file_to_install}))"
	if [ -f "${file}" ]; then
		# try to umount it first, it can be mounted as a read-only file
		sudo umount "${file}" || true
		sudo rm -f "${file}"
	fi
	sudo install -D "${file_to_install}" "${image_path}"
	popd
}

main() {
	build_rust_image
}

main
