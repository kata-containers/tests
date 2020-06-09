#!/bin/bash
#
# Copyright (c) 2018-2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -e

cidir=$(dirname "$0")
source "/etc/os-release" || source "/usr/lib/os-release"
source "${cidir}/lib.sh"
export DEBIAN_FRONTEND=noninteractive

echo "Install chronic"
sudo -E apt -y install moreutils

declare -A minimal_packages=( \
	[spell-check]="hunspell hunspell-en-gb hunspell-en-us pandoc" \
	[xml_validator]="libxml2-utils" \
	[yaml_validator]="yamllint" \
)

declare -A packages=( \
	[bison_binary]="bison" \
	[build_tools]="build-essential pkg-config python zlib1g-dev" \
	[cri-containerd_dependencies]="gcc libapparmor-dev libbtrfs-dev libseccomp-dev make pkg-config" \
	[crio_dependencies]="go-md2man libapparmor-dev libglib2.0-dev libgpgme11-dev libseccomp-dev thin-provisioning-tools" \
	[crio_dependencies_for_debian]="libdevmapper-dev util-linux" \
	[crudini]="crudini" \
	[general_dependencies]="curl git xfsprogs" \
	[gnu_parallel]="parallel" \
	[haveged]="haveged" \
	[kata_containers_dependencies]="autoconf automake autotools-dev bc coreutils libpixman-1-dev libtool parted" \
	[kernel_dependencies]="flex libelf-dev" \
	[libsystemd]="libsystemd-dev" \
	[libudev-dev]="libudev-dev" \
	[metrics_dependencies]="jq" \
	[os_tree]="libostree-dev" \
	[procenv]="procenv" \
	[qemu_dependencies]="libattr1-dev libcap-dev libcap-ng-dev librbd-dev libpmem-dev libselinux1-dev libffi-dev libmount-dev libblkid-dev" \
	[redis]="redis-server" \
)

main()
{
	local setup_type="$1"
	[ -z "$setup_type" ] && die "need setup type"

	local pkgs_to_install
	local pkgs

	for pkgs in "${minimal_packages[@]}"; do
		info "The following package will be installed: $pkgs"
		pkgs_to_install+=" $pkgs"
	done

	if [ "$setup_type" = "default" ]; then
		for pkgs in "${packages[@]}"; do
			info "The following package will be installed: $pkgs"
			pkgs_to_install+=" $pkgs"
		done
	fi

	chronic sudo -E apt -y install $pkgs_to_install

	[ "$setup_type" = "minimal" ] && exit 0

	if [ "$KATA_KSM_THROTTLER" == "yes" ]; then
		echo "Install ${KATA_KSM_THROTTLER_JOB}"
		chronic sudo -E apt install -y ${KATA_KSM_THROTTLER_JOB}
	fi
}

main "$@"
