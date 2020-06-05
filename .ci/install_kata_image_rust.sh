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
osbuilder_repo="github.com/kata-containers/osbuilder"
arch=$("${cidir}"/kata-arch.sh -d)

build_rust_image() {
	go get -d "${osbuilder_repo}" || true
	export RUST_AGENT="yes"
	osbuilder_path="${GOPATH}/src/${osbuilder_repo}"
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
