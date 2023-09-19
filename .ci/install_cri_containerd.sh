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

SNAPSHOTTER=${SNAPSHOTTER:-""}

# shellcheck source=./lib.sh
source "${script_dir}/lib.sh"

#Use cri contaienrd tarball format.
#https://github.com/containerd/containerd/blob/main/docs/cri/installation.md#release-tarball
CONTAINERD_OS=$(go env GOOS)
CONTAINERD_ARCH=$(go env GOARCH)

if [ "${FORKED_CONTAINERD}" = "yes" ]; then
	containerd_tarball_version=$(get_version "externals.containerd.forked.version")
else
	containerd_tarball_version=$(get_version "externals.containerd.upstream.version")
fi

containerd_version=${containerd_tarball_version#v}

echo "Set up environment"
if [ "$ID" == centos ] || [ "$ID" == rhel ] || [ "$ID" == sles ]; then
	# CentOS/RHEL/SLES: remove seccomp from runc build, no btrfs
	export BUILDTAGS=${BUILDTAGS:-apparmor no_btrfs}
fi

install_from_source() {
	echo "Trying to install containerd from source"
	(
		if [ "${FORKED_CONTAINERD}" = "yes" ]; then
			containerd_repo=$(get_version "externals.containerd.forked.url")
		else
			containerd_repo=$(get_version "externals.containerd.upstream.url")
		fi
		cd ${GOPATH}/src/
		git clone "https://${containerd_repo}.git" "${GOPATH}/src/${containerd_repo}"

		add_repo_to_git_safe_directory "${GOPATH}/src/${containerd_repo}"

		cd "${GOPATH}/src/${containerd_repo}"
		git fetch
		git checkout "${containerd_tarball_version}"
		make BUILD_TAGS="${BUILDTAGS:-}" cri-cni-release
		tarball_name="cri-containerd-cni-${containerd_version}-${CONTAINERD_OS}-${CONTAINERD_ARCH}.tar.gz"
		sudo tar -xvf "./releases/${tarball_name}" -C /
	)
}

install_from_static_tarball() {
	echo "Trying to install containerd from static tarball"
	if [ "${FORKED_CONTAINERD}" = "yes" ]; then
		local tarball_url=$(get_version "externals.containerd.forked.tarball_url")
	else
		local tarball_url=$(get_version "externals.containerd.upstream.tarball_url")
	fi

	local tarball_name="cri-containerd-cni-${containerd_version}-${CONTAINERD_OS}-${CONTAINERD_ARCH}.tar.gz"
	local url="${tarball_url}/${containerd_tarball_version}/${tarball_name}"

	echo "Download tarball from ${url}"
	if ! curl -OL -f "${url}"; then
		echo "Failed to download tarball from ${url}"
		return 1
	fi

	sudo tar -xvf "${tarball_name}" -C /
}

install_vanilla_from_static_tarball() {
	echo "Trying to install containerd from static tarball"
	local tarball_url="https://github.com/containerd/containerd/releases/download"
	local containerd_tarball_version="v1.7.0"
	local containerd_version=${containerd_tarball_version#v}
	local tarball_name="containerd-${containerd_version}-${CONTAINERD_OS}-${CONTAINERD_ARCH}.tar.gz"
	local url="${tarball_url}/${containerd_tarball_version}/${tarball_name}"

	echo "Download tarball from ${url}"
	if ! curl -OL -f "${url}"; then
		echo "Failed to download tarball from ${url}"
		return 1
	fi

	tmp_dir=$(mktemp -d -t install-vanilla-containerd-tmp.XXXXXXXXXX)
	sudo tar -xvf "${tarball_name}" -C $tmp_dir/
	sudo install -D -m 755 "$tmp_dir/bin/containerd" "/usr/local/bin/containerd-vanilla"

	systemctl status containerd
}

install_cri-tools() {
	crictl_repo=$(get_version "externals.critools.url")
	crictl_version=$(get_version "externals.critools.version")
	crictl_tag_prefix="v"

	crictl_url="${crictl_repo}/releases/download/v${crictl_version}/crictl-${crictl_tag_prefix}${crictl_version}-linux-$(${script_dir}/kata-arch.sh -g).tar.gz"
	curl -Ls "$crictl_url" | sudo tar xfz - -C /usr/local/bin
}

install_from_static_tarball || install_from_source

if [ "${SNAPSHOTTER}" == "nydus" ]; then
	install_vanilla_from_static_tarball
fi

install_cri-tools

sudo systemctl daemon-reload
