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
	export RUST_AGENT="yes"
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
			if [ ${CCV0} == "yes"]; then
				# CCv0 is using skopeo and gpg packages and we've added a few more for debugging. The default distro of ubuntu is really back level, so some are missing there, so use fedora
				# We also need to split the rootfs create and image build so we can add umoci to the rootfs directly
				distro=fedora
				EXTRA_PKGS="skopeo gnupg gpgme-devel vim iputils net-tools iproute"
				sudo -E USE_DOCKER="${use_docker:-}" DISTRO="${distro}" EXTRA_PKGS="${EXTRA_PKGS}" \
					make -e "rootfs"
				rootfs_target="$(shell pwd)/$(DISTRO)_rootfs"
				# CCv0 is using umoci which isn't in a fedora package we can access yet, so grabbing from their webstire
				go_arch=$("${cidir}"/kata-arch.sh -g)
				mkdir -p ${rootfs_target}/usr/local/bin/
				sudo curl -Lo ${rootfs_target}/usr/local/bin/umoci https://github.com/opencontainers/umoci/releases/download/v0.4.7/umoci.${go_arch}
				sudo chmod u+x ${rootfs_target}/usr/local/bin/umoci
				sudo -E USE_DOCKER="${use_docker:-}" DISTRO="${distro}" \
					make -e "image"
			else
				distro="${osbuilder_distro:-ubuntu}"
				if [[ ! "${osbuild_docker:-}" =~ ^(0|false|no)$ ]]; then
					use_docker="${osbuild_docker:-}"
					[[ -z "${USE_PODMAN:-}" ]] && use_docker="${use_docker:-1}"
				fi
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
