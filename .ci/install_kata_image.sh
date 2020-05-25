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

build_rust_image() {
	export RUST_AGENT="yes"
	osbuilder_path="${GOPATH}/src/${rust_agent_repo}/tools/osbuilder"
	distro="ubuntu"

	pushd "${osbuilder_path}"
	echo "Building rust image"
	sudo -E USE_DOCKER=1 DISTRO="${distro}" make -e image

	image_path="/usr/share/kata-containers/"
	sudo mkdir -p "${image_path}"
	echo "Install rust image to ${image_path}"
	sudo install -D "${osbuilder_path}/kata-containers.img" "${image_path}"
	popd
}

main() {
	build_rust_image
}

main
