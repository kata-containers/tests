#!/bin/bash
#
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

readonly script_dir=$(dirname $(readlink -f "$0"))

cidir=$(dirname "$0")
arch=$("${cidir}"/kata-arch.sh -d)
source "${cidir}/lib.sh"

main() {
	# Just in case the kata-containers repo is not cloned yet.
	clone_katacontainers_repo

	pushd $katacontainers_repo_dir
	sudo -E PATH=$PATH make cloud-hypervisor-tarball
	sudo tar xvJpf build/kata-static-cloud-hypervisor.tar.xz -C /
	sudo ln -sf /opt/kata/bin/cloud-hypervisor /usr/bin/cloud-hypervisor
	popd
}

main "$@"
