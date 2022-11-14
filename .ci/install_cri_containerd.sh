#!/bin/bash
#
# Copyright (c) 2018-2020 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
set -x

source /etc/os-release || source /usr/lib/os-release

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Flag to do tasks for CI
CI=${CI:-""}

# shellcheck source=./lib.sh
source "${script_dir}/lib.sh"

#Use cri contaienrd tarball format.
#https://github.com/containerd/containerd/blob/main/docs/cri/installation.md#release-tarball
CONTAINERD_OS=$(go env GOOS)
CONTAINERD_ARCH=$(go env GOARCH)

containerd_tarball_version=$(get_version "externals.containerd.version")

containerd_version=${containerd_tarball_version#v}

echo "Set up environment"
if [ "$ID" == centos ] || [ "$ID" == rhel ] || [ "$ID" == sles ]; then
	# CentOS/RHEL/SLES: remove seccomp from runc build, no btrfs
	export BUILDTAGS=${BUILDTAGS:-apparmor no_btrfs}
fi

install_from_source() {
	echo "Trying to install containerd from source"
	(
		containerd_repo=$(get_version "externals.containerd.url")
		pushd "${GOPATH}/src/github.com"
		git clone "https://${containerd_repo}"
		popd

		cd "${GOPATH}/src/github.com/containerd" >>/dev/null
		add_repo_to_git_safe_directory "${GOPATH}/src/github.com/containerd"

		git fetch
		git checkout "${containerd_tarball_version}"
		make BUILD_TAGS="${BUILDTAGS:-}" cri-cni-release
		tarball_name="cri-containerd-cni-${containerd_version}-${CONTAINERD_OS}-${CONTAINERD_ARCH}.tar.gz"
		sudo tar -xvf "./releases/${tarball_name}" -C /
	)
}

install_from_static_tarball() {
	echo "Trying to install containerd from static tarball"
	local tarball_url=$(get_version "externals.containerd.tarball_url")

	local tarball_name="cri-containerd-cni-${containerd_version}-${CONTAINERD_OS}-${CONTAINERD_ARCH}.tar.gz"
	local url="${tarball_url}/${containerd_tarball_version}/${tarball_name}"

	echo "Download tarball from ${url}"
	if ! curl -OL -f "${url}"; then
		echo "Failed to download tarball from ${url}"
		return 1
	fi

	sudo tar -xvf "${tarball_name}" -C /
}

install_from_static_tarball || install_from_source

sudo systemctl daemon-reload
