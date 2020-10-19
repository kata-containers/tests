#!/bin/bash
#
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -e

cidir=$(dirname "$0")
source "/etc/os-release" || source "/usr/lib/os-release"
source "${cidir}/lib.sh"
arch=$("${cidir}"/kata-arch.sh -d)

echo "Add PackageHub repositories for additional dependencies which are not part of the main distro"
sudo -E SUSEConnect -p PackageHub/${VERSION_ID}/${arch}
sudo -E zypper refresh

echo "Install chronic"
sudo -E zypper -n install moreutils

declare -A minimal_packages=( \
	[spell-check]="hunspell myspell-en myspell-en_US pandoc" \
	[xml_validator]="libxml2-tools" \
	[yaml_validator]="python3-yamllint" \
)

declare -A packages=( \
	[bison_binary]="bison" \
	[build_tools]="gcc python zlib-devel" \
	[cri-containerd_dependencies]="libapparmor-devel libseccomp-devel make pkg-config" \
	[crio_dependencies]="glibc-devel glibc-devel-static glib2-devel libapparmor-devel libgpg-error-devel libglib-2_0-0 libgpgme-devel libseccomp-devel libassuan-devel util-linux" \
	[crudini]="crudini" \
	[general_dependencies]="curl git patch xfsprogs perl-IPC-Run" \
	[gnu_parallel]="gnu_parallel" \
	[haveged]="haveged" \
	[kata_containers_dependencies]="autoconf automake bc coreutils libpixman-1-0-devel libtool" \
	[kernel_dependencies]="flex libelf-devel patch" \
	[libsystemd]="systemd-devel" \
	[libudev-dev]="libudev-devel" \
	[metrics_dependencies]="jq" \
	[qemu_dependencies]="libattr1 libcap-devel libcap-ng-devel libpmem-devel librbd-devel libselinux-devel libffi-devel libmount-devel libblkid-devel" \
	[redis]="redis" \
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

	chronic sudo -E zypper -n install $pkgs_to_install
}

main "$@"
