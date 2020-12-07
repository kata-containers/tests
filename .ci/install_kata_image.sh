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
rust_agent_repo="github.com/kata-containers/kata-containers"
arch=$("${cidir}"/kata-arch.sh -d)
PREFIX="${PREFIX:-/usr}"
DESTDIR="${DESTDIR:-/}"
image_path="${DESTDIR}${image_path:-${PREFIX}/share/kata-containers}"
image_name="${image_name:-kata-containers.img}"
initrd_name="${initrd_name:-kata-containers-initrd.img}"
AGENT_INIT="${AGENT_INIT:-no}"
TEST_INITRD="${TEST_INITRD:-no}"

build_rust_image() {
	export RUST_AGENT="yes"
	osbuilder_path="${GOPATH}/src/${rust_agent_repo}/tools/osbuilder"
	distro="ubuntu"

	sudo mkdir -p "${image_path}"

	pushd "${osbuilder_path}"

	if [ "${TEST_INITRD}" == "no" ]; then
		echo "Building image with AGENT_INIT=${AGENT_INIT}"
		sudo -E USE_DOCKER=1 DISTRO="${distro}" make -e image

		echo "Install image to ${image_path}"
		sudo install -D "${osbuilder_path}/${image_name}" "${image_path}"
	else
		echo "Building initrd with AGENT_INIT=${AGENT_INIT}"
		sudo -E USE_DOCKER=1 DISTRO="${distro}" make -e initrd

		echo "Install initrd to ${image_path}"
		sudo install -D "${osbuilder_path}/${initrd_name}" "${image_path}"
	fi

	popd
}

main() {
	build_rust_image
}

main
