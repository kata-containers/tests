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
#https://github.com/containerd/cri/blob/master/docs/installation.md#release-tarball
CONTAINERD_OS=$(go env GOOS)
CONTAINERD_ARCH=$(go env GOARCH)

cri_containerd_tarball_version=$(get_version "externals.cri-containerd.version")
cri_containerd_repo=$(get_version "externals.cri-containerd.url")

cri_containerd_version=${cri_containerd_tarball_version#v}
cri_containerd_pr=$(get_version "externals.cri-containerd.pr_id")

echo "Set up environment"
if [ "$ID" == centos ] || [ "$ID" == rhel ] || [ "$ID" == sles ]; then
	# CentOS/RHEL/SLES: remove seccomp from runc build, no btrfs
	export BUILDTAGS=${BUILDTAGS:-apparmor no_btrfs}
fi

install_from_source() {
	echo "Trying to install containerd from source"
	(
		cd "${GOPATH}/src/${cri_containerd_repo}" >>/dev/null
		git fetch
		git checkout "${cri_containerd_tarball_version}"
		make BUILD_TAGS="${BUILDTAGS:-}" cri-cni-release
		tarball_name="cri-containerd-cni-${cri_containerd_version}-${CONTAINERD_OS}-${CONTAINERD_ARCH}.tar.gz"
		sudo tar -xvf "./releases/${tarball_name}" -C /
	)
}

install_from_pr() {
	warn "Using patched Confidential Computing containerd version: see https://github.com/containerd/containerd/pull/${cri_containerd_pr}"
	echo "Trying to install containerd from a PR"
	(
		cd "${GOPATH}/src/${cri_containerd_repo}" >>/dev/null
		git fetch origin pull/${cri_containerd_pr}/head:PR_BRANCH
		git checkout "PR_BRANCH"
		make BUILD_TAGS="${BUILDTAGS:-}" cri-cni-release
		# SH: The PR containerd version might not match the version.yaml one, so get from build
		cri_containerd_version=$(_output/cri/bin/containerd --version | awk '{ print substr($3,2); }')
		tarball_name="cri-containerd-cni-${cri_containerd_version}-${CONTAINERD_OS}-${CONTAINERD_ARCH}.tar.gz"
		echo "Tarball name is : '${tarball_name}'"
		sudo tar -xvf "./releases/${tarball_name}" -C /
		# Clean up PR_BRANCH
		git checkout main && git branch -D "PR_BRANCH"
	)
}

install_from_static_tarball() {
	echo "Trying to install containerd from static tarball"
	local tarball_url=$(get_version "externals.cri-containerd.tarball_url")

	local tarball_name="cri-containerd-cni-${cri_containerd_version}-${CONTAINERD_OS}-${CONTAINERD_ARCH}.tar.gz"
	local url="${tarball_url}/${cri_containerd_tarball_version}/${tarball_name}"

	echo "Download tarball from ${url}"
	if ! curl -OL -f "${url}"; then
		echo "Failed to download tarball from ${url}"
		return 1
	fi

	sudo tar -xvf "${tarball_name}" -C /
}

go get "${cri_containerd_repo}"

# For 'CCv0' we are pulling in a PR of containerd with our custom code
if [ -n ${cri_containerd_pr} ]; then
  install_from_pr
else
  install_from_static_tarball || install_from_source
fi

sudo systemctl daemon-reload
