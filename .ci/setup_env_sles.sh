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

echo "Add repo for perl-IPC-Run"
perl_repo="https://download.opensuse.org/repositories/devel:languages:perl/SLE_${VERSION//-/_}/devel:languages:perl.repo"
sudo -E zypper addrepo --no-gpgcheck ${perl_repo}
sudo -E zypper refresh

echo "Add repo for myspell"
leap_repo="http://download.opensuse.org/update/leap/15.0/oss/"
leap_repo_name="leap-oss"
sudo -E zypper addrepo --no-gpgcheck ${leap_repo} ${leap_repo_name}
sudo -E zypper refresh  ${leap_repo_name}

echo "Install perl-IPC-Run"
sudo -E zypper -n install perl-IPC-Run

echo "Add repo for filesystems"
filesystems_repo="https://download.opensuse.org/repositories/filesystems/SLE_${VERSION//-/_}/filesystems.repo"
sudo -E zypper refresh
sudo -E zypper -n install xfsprogs

echo "Add repo for hunspell and pandoc packages"
sudo -E SUSEConnect -p PackageHub/${VERSION_ID}/${arch}

echo "Install chronic"
sudo -E zypper -n install moreutils

declare -A minimal_packages=( \
	[spell-check]="hunspell myspell-en_GB myspell-en_US pandoc" \
	[xml_validator]="libxml2-tools" \
	[yaml_validator_dependencies]="python-setuptools" \
)

declare -A packages=( \
	[bison_binary]="bison" \
	[build_tools]="gcc python zlib-devel" \
	[cri-containerd_dependencies]="libapparmor-devel libseccomp-devel make pkg-config" \
	[crio_dependencies]="glibc-devel glibc-devel-static glib2-devel libapparmor-devel libgpg-error-devel libglib-2_0-0 libgpgme-devel libseccomp-devel libassuan-devel util-linux" \
	[general_dependencies]="curl git patch" \
	[gnu_parallel]="gnu_parallel" \
	[haveged]="haveged" \
	[kata_containers_dependencies]="autoconf automake bc coreutils libpixman-1-0-devel libtool" \
	[kernel_dependencies]="flex libelf-devel patch" \
	[libsystemd]="systemd-devel" \
	[libudev-dev]="libudev-devel" \
	[metrics_dependencies]="jq" \
	[qemu_dependencies]="libattr1 libcap-devel libcap-ng-devel libpmem-devel librbd-devel libselinux-devel libffi-devel libmount-devel libblkid-devel" \
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

	echo "Add redis repo and install redis"
	redis_repo="https://download.opensuse.org/repositories/server:database/SLE_${VERSION//-/_}/server:database.repo"
	chronic sudo -E zypper addrepo --no-gpgcheck ${redis_repo}
	chronic sudo -E zypper refresh
	chronic sudo -E zypper -n install redis

	[ "$setup_type" = "minimal" ] && exit 0

	echo "Add crudini repo"
	VERSIONID="12_SP1"
	crudini_repo="https://download.opensuse.org/repositories/Cloud:OpenStack:Liberty/SLE_${VERSIONID}/Cloud:OpenStack:Liberty.repo"
	chronic sudo -E zypper addrepo --no-gpgcheck ${crudini_repo}
	chronic sudo -E zypper refresh
	chronic sudo -E zypper -n install crudini
}

main "$@"
