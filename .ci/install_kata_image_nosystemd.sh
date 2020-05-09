#!/bin/bash
#
# Copyright (c) 2020 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

cidir=$(dirname "$0")
rust_agent_repo="github.com/kata-containers/kata-containers"
osbuilder_repo="github.com/kata-containers/osbuilder"
arch=$("${cidir}"/kata-arch.sh -d)

build_image() {
	go get -d "${osbuilder_repo}" || true
	pushd "${GOPATH}/src/${osbuilder_repo}/rootfs-builder"
	export ROOTFS_DIR="${GOPATH}/src/${osbuilder_repo}/rootfs-builder/rootfs"

	#Currently, only alpine support no systemd"
	distro="alpine"
	sudo -E GOPATH="${GOPATH}" USE_DOCKER=true SECCOMP=no ./rootfs.sh "${distro}"
	install -o root -g root -m 0550 -T ../../agent/kata-agent ${ROOTFS_DIR}/sbin/init
	popd

	pushd "${GOPATH}/src/${osbuilder_repo}"
	sudo -E USE_DOCKER=1 DISTRO="${distro}" AGENT_INIT=yes ./image-builder/image_builder.sh ${ROOTFS_DIR}

	image_path="/usr/share/kata-containers/"
	sudo mkdir -p "${image_path}"
	sudo install -D "${GOPATH}/src/${osbuilder_repo}/kata-containers.img" "${image_path}"
	popd
}

main() {
	build_image
}

main
