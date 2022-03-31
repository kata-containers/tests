#!/bin/bash
#
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o nounset
set -o pipefail

cidir=$(dirname "$0")
arch=$("${cidir}"/kata-arch.sh -d)
source "${cidir}/lib.sh"
KATA_DEV_MODE="${KATA_DEV_MODE:-false}"
ghprbGhRepository="${ghprbGhRepository:-}"

if [ "$KATA_DEV_MODE" = true ]; then
	die "KATA_DEV_MODE set so not running the test"
fi

install_fc() {
	# Get url for firecracker from runtime/versions.yaml
	firecracker_repo=$(get_version "assets.hypervisor.firecracker.url")
	[ -n "$firecracker_repo" ] || die "failed to get firecracker repo"

	# Get version for firecracker from runtime/versions.yaml
	firecracker_version=$(get_version "assets.hypervisor.firecracker.version")
	[ -n "$firecracker_version" ] || die "failed to get firecracker version"

	# Download firecracker and jailer
	firecracker_binary="firecracker-${firecracker_version}-${arch}"
	jailer_binary="jailer-${firecracker_version}-${arch}"
	curl -fsL ${firecracker_repo}/releases/download/${firecracker_version}/${firecracker_binary}.tgz -o ${firecracker_binary}.tgz
	tar -zxf ${firecracker_binary}.tgz
	firecracker_binary_fullpath=release-${firecracker_version}/${firecracker_binary}
	jailer_binary_fullpath=release-${firecracker_version}/${jailer_binary}
	sudo -E install -m 0755 -D ${firecracker_binary_fullpath} /usr/bin/firecracker
	sudo -E install -m 0755 -D ${jailer_binary_fullpath} /usr/bin/jailer
}

main() {
	# Install FC only when testing changes on Kata repos.
	# If testing changes on firecracker repo, skip installation as it is
	# done in the CI jenkins job.
	if [ "${ghprbGhRepository}" != "firecracker-microvm/firecracker" ]; then
		install_fc
	fi
}

main "$@"
