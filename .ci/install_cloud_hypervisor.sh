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
# Where real kata build script exist, via docker build to avoid install all deps
latest_build_url="${jenkins_url}/job/cloud-hypervisor-nightly-$(uname -m)/${cached_artifacts_path}"
clh_bin_name="cloud-hypervisor"
clh_install_path="/usr/bin/${clh_bin_name}"
cloud_hypervisor_repo=$(get_version "assets.hypervisor.cloud_hypervisor.url")
go_cloud_hypervisor_repo=${cloud_hypervisor_repo/https:\/\//}

install_clh() {
	[ -n "$cloud_hypervisor_repo" ] || die "failed to get cloud_hypervisor repo"
	export cloud_hypervisor_repo

	# Get version for cloud_hypervisor from runtime/versions.yaml
	cloud_hypervisor_version=$(get_version "assets.hypervisor.cloud_hypervisor.version")
	[ -n "$cloud_hypervisor_version" ] || die "failed to get cloud_hypervisor version"
	export cloud_hypervisor_version

	# Get cloud_hypervisor repo
	go get -d "${go_cloud_hypervisor_repo}" || true
	# This may be downloaded before if there was a depends-on in PR, but 'go get' wont make any problem here
	go get -d "${packaging_repo}" || true
	pushd  $(dirname "${GOPATH}/src/${go_cloud_hypervisor_repo}")
	# packaging build script expects run in the hypervisor repo parent directory
	# It will find the hypervisor repo and checkout to the version exported above
	"${GOPATH}/src/${packaging_repo}/static-build/cloud-hypervisor/build-static-clh.sh"
	sudo install -D "cloud-hypervisor/${clh_bin_name}"  "${clh_install_path}"
	popd
}

install_prebuilt_clh() {
	local checksum_file="sha256sum-cloud-hypervisor"
	go get -d "${go_cloud_hypervisor_repo}" || true
	pushd  "${GOPATH}/src/${go_cloud_hypervisor_repo}"

	info "Downloading hypervisor binary"
	curl -fOL --progress-bar "${latest_build_url}/${clh_bin_name}" || return 1
	info "Downloading hypervisor binary checksum"
	curl -fOL --progress-bar "${latest_build_url}/${checksum_file}" || return 1

	info "Verify download checksum"
	sudo sha256sum -c "${checksum_file}" || return 1

	info "installing ${clh_bin_name}" "${clh_install_path}"
	sudo install -D ${clh_bin_name} "${clh_install_path}"
	popd
}

main() {
	current_cloud_hypervisor_version=$(get_version "assets.hypervisor.cloud_hypervisor.version")
	cached_cloud_hypervisor_version=$(curl -sfL "${latest_build_url}/latest") || cached_cloud_hypervisor_version="none"
	info "current cloud hypervisor : ${current_cloud_hypervisor_version}"
	info "cached cloud hypervisor  : ${cached_cloud_hypervisor_version}"
        # enforce to install clh from source to validate whether clh is built statically
	install_clh
}

main "$@"
