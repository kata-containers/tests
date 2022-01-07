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
containerd_branch=$(get_version "externals.containerd.branch")

echo "Set up environment "
if [ "$ID" == centos ] || [ "$ID" == rhel ] || [ "$ID" == sles ]; then
	# CentOS/RHEL/SLES: remove seccomp from runc build, no btrfs
	export BUILDTAGS=${BUILDTAGS:-apparmor no_btrfs}
fi

install_from_source() {
	echo "Trying to install containerd from source"
	(
		containerd_repo=$(get_version "externals.containerd.url")
		go get "${containerd_repo}"
		cd "${GOPATH}/src/${containerd_repo}" >>/dev/null
		git fetch
		git checkout "${containerd_tarball_version}"
		make BUILD_TAGS="${BUILDTAGS:-}" cri-cni-release
		tarball_name="cri-containerd-cni-${containerd_version}-${CONTAINERD_OS}-${CONTAINERD_ARCH}.tar.gz"
		sudo tar -xvf "./releases/${tarball_name}" -C /
	)
}

install_from_branch() {
	containerd_repo=$(get_version "externals.containerd.url")
	warn "Using patched Confidential Computing containerd version: see https://${containerd_repo}/tree/${containerd_branch}"
	echo "Trying to install containerd from a branch"
	(
		go get -d "${containerd_repo}"
		cd "${GOPATH}/src/${containerd_repo}" >>/dev/null
		git fetch
		git checkout "${containerd_branch}"
		sudo -E PATH="$PATH" make BUILD_TAGS="${BUILDTAGS:-}" cri-cni-release
		# SH: The PR containerd version might not match the version.yaml one, so get from build
		containerd_version=$(_output/cri/bin/containerd --version | awk '{ print substr($3,2); }')
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

# For 'CCv0' we are pulling in a branch of our confidential-containers fork of containerd with our custom code
if [ -n ${containerd_branch} ]; then
  install_from_branch
else
  install_from_static_tarball || install_from_source
fi

sudo systemctl daemon-reload
