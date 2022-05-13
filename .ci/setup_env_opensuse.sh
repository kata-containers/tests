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

echo "Install chronic"
sudo -E zypper -n install moreutils

declare -A minimal_packages=( \
	[spell-check]="hunspell myspell-en_GB myspell-en_US" \
	[xml_validator]="libxml2-tools" \
	[yaml_validator_dependencies]="python-setuptools" \
)

declare -A packages=( \
	[general_dependencies]="curl git libcontainers-common libdevmapper1_03 util-linux expect" \
	[kata_containers_dependencies]="libtool automake autoconf bc perl-Alien-SDL libpixman-1-0-devel coreutils python2-pkgconfig" \
	[qemu_dependencies]="libcap-devel libattr1 libcap-ng-devel librbd-devel ninja" \
	[kernel_dependencies]="libelf-devel flex glibc-devel-static thin-provisioning-tools" \
	[crio_dependencies]="libglib-2_0-0 libseccomp-devel libapparmor-devel libgpg-error-devel go-md2man libgpgme-devel libassuan-devel glib2-devel glibc-devel" \
	[gperf_dependencies]="gcc-c++" \
	[bison_binary]="bison" \
	[build_tools]="gcc python pkg-config zlib-devel" \
	[os_tree]="libostree-devel" \
	[libudev-dev]="libudev-devel" \
	[metrics_dependencies]="smemstat jq" \
	[cri-containerd_dependencies]="libseccomp-devel libapparmor-devel make pkg-config libbtrfs-devel patterns-base-apparmor" \
	[crudini]="crudini" \
	[haveged]="haveged" \
	[libsystemd]="systemd-devel" \
	[redis]="redis" \
	[agent_shutdown_test]="tmux" \
	[virtiofsd_dependencies]="unzip" \
)

if [ "${arch}" == "x86_64" ] || [ "${arch}" == "ppc64le" ]; then
	packages[qemu_dependencies]+=" libpmem-devel"
fi

if [ "$(uname -m)" == "ppc64le" ] || [ "$(uname -m)" == "s390x" ]; then
	packages[kata_containers_dependencies]+=" protobuf-devel"
fi

if [ "$(uname -m)" == "s390x" ]; then
	packages[kernel_dependencies]+=" libopenssl-devel"
fi

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

	# Pandoc currently unavailable in openSUSE s390x repos
	# Allow install failure, is not required for mainstream CI workflow
	echo "Try to install pandoc"
	sudo -E zypper -n install pandoc || true

	echo "Install YAML validator"
	chronic sudo -E easy_install pip
	chronic sudo -E pip install yamllint
}

main "$@"
