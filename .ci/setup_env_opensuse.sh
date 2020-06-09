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

# This is related with https://bugzilla.suse.com/show_bug.cgi?id=1165519
echo "Remove openSUSE cloud repo"
sudo zypper rr openSUSE-Leap-Cloud-Tools

echo "Add filesystems repo"
filesystem_repo="https://download.opensuse.org/repositories/filesystems/openSUSE_Leap_${VERSION_ID}/filesystems.repo"
sudo -E zypper addrepo --no-gpgcheck "${filesystem_repo}"
sudo -E zypper -n install xfsprogs

echo "Install chronic"
sudo -E zypper -n install moreutils

declare -A minimal_packages=( \
	[spell-check]="hunspell myspell-en_GB myspell-en_US pandoc" \
	[xml_validator]="libxml2-tools" \
	[yaml_validator_dependencies]="python-setuptools" \
)

declare -A packages=( \
	[bison_binary]="bison" \
	[build_tools]="gcc pkg-config python zlib-devel" \
	[cri-containerd_dependencies]="libapparmor-devel libbtrfs-devel libseccomp-devel make patterns-base-apparmor pkg-config" \
	[crio_dependencies]="glibc-devel glib2-devel go-md2man libassuan-devel libapparmor-devel libgpg-error-devel libglib-2_0-0 libgpgme-devel libseccomp-devel" \
	[crudini]="crudini" \
	[general_dependencies]="curl git libcontainers-common libdevmapper1_03 util-linux" \
	[gnu_parallel]="gnu_parallel" \
	[haveged]="haveged" \
	[kata_containers_dependencies]="autoconf automake bc coreutils libpixman-1-0-devel libtool perl-Alien-SDL python2-pkgconfig" \
	[kernel_dependencies]="flex glibc-devel-static libelf-devel patch thin-provisioning-tools" \
	[libsystemd]="systemd-devel" \
	[libudev-dev]="libudev-devel" \
	[metrics_dependencies]="jq smemstat" \
	[os_tree]="libostree-devel" \
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

	echo "Install YAML validator"
	chronic sudo -E easy_install pip
	chronic sudo -E pip install yamllint
}

main "$@"
