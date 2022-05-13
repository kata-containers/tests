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

cidir=$(dirname "$0")
source "${cidir}/lib.sh"

main() {
	local buildscript="${katacontainers_repo_dir}/tools/packaging/kata-deploy/local-build/kata-deploy-binaries.sh"

	# Just in case the kata-containers repo is not cloned yet.
	clone_katacontainers_repo

	pushd $katacontainers_repo_dir
	sudo -E PATH=$PATH bash ${buildscript} --build=cloud-hypervisor
	sudo tar xvJpf build/kata-static-cloud-hypervisor.tar.xz -C /
	sudo ln -sf /opt/kata/bin/cloud-hypervisor /usr/bin/cloud-hypervisor
	popd
}

main "$@"
