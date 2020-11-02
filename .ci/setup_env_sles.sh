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

# Use at least openSUSE 15.3 on s390x because that is the first release
major="${VERSION_ID%.*}"
minor="${VERSION_ID#*.}"
[ "${arch}" == "s390x" ] && ([[ "${major}" -le 12 ]] || ([ "${major}" == "15" ] && [ "${minor}" -le 2 ])) && \
	VERSION_ID="15.3"

leap_repo="http://download.opensuse.org/distribution/leap/${VERSION_ID}/repo/oss/"
leap_repo_name="leap-oss"
sudo -E zypper removerepo ${leap_repo} || true
sudo -E zypper addrepo --no-gpgcheck ${leap_repo} ${leap_repo_name}
sudo -E zypper refresh  ${leap_repo_name}

echo "Install perl-IPC-Run"
sudo -E zypper -n install perl-IPC-Run

echo "Install chronic"
sudo -E zypper -n install moreutils

declare -A minimal_packages=( \
	[spell-check]="hunspell myspell-en_GB myspell-en_US" \
	[xml_validator]="libxml2-tools" \
	[yaml_validator_dependencies]="python-setuptools" \
)

declare -A packages=( \
	[general_dependencies]="curl git patch expect"
	[kata_containers_dependencies]="libtool automake autoconf bc libpixman-1-0-devel coreutils" \
	[qemu_dependencies]="libcap-devel libattr1 libcap-ng-devel librbd-devel ninja" \
	[kernel_dependencies]="libelf-devel flex" \
	[crio_dependencies]="libglib-2_0-0 libseccomp-devel libapparmor-devel libgpg-error-devel glibc-devel-static libgpgme-devel libassuan-devel glib2-devel glibc-devel util-linux" \
	[gperf_dependencies]="gcc-c++" \
	[bison_binary]="bison" \
	[libudev-dev]="libudev-devel" \
	[build_tools]="gcc python zlib-devel" \
	[metrics_dependencies]="jq" \
	[cri-containerd_dependencies]="libseccomp-devel libapparmor-devel make pkg-config" \
	[haveged]="haveged" \
	[libsystemd]="systemd-devel" \
	[agent_shutdown_test]="tmux" \
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

	echo "Install redis"
	chronic sudo -E zypper -n install redis

	[ "$setup_type" = "minimal" ] && exit 0

	echo "Install crudini"
	chronic sudo -E zypper -n install crudini
}

main "$@"
