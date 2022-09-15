#!/bin/bash
# Copyright 2022 Advanced Micro Devices, Inc.
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
	sudo -E PATH=$PATH bash ${buildscript} --build=cc-sev-ovmf
	sudo tar -xvJpf build/kata-static-cc-sev-ovmf.tar.xz -C /
	sudo ln -sf /opt/confidential-containers/share/ovmf /usr/share/ovmf
	popd
}

main "$@"
