#!/bin/bash
#
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -e

cidir=$(dirname "$0")
source "/etc/os-release" || "source /usr/lib/os-release"
source "${cidir}/lib.sh"

rhel_version=$(sed -E "s/.*:el(.+)/\1/" <<< "${PLATFORM_ID}")

echo "Add epel repository"
epel_url="https://dl.fedoraproject.org/pub/epel/epel-release-latest-${rhel_version}.noarch.rpm"
sudo -E yum install -y "$epel_url"

echo "Update repositories"
sudo -E yum -y --nobest update

echo "Install chronic"
sudo -E yum install -y moreutils

declare -A minimal_packages=( \
	[spell-check]="hunspell hunspell-en-GB hunspell-en-US pandoc" \
	[xml_validator]="libxml2" \
	[yamllint]="yamllint"
)

declare -A packages=(
	[kata_containers_dependencies]="libtool libtool-ltdl-devel device-mapper-persistent-data lvm2 device-mapper-devel libtool-ltdl bzip2 m4 patch gettext-devel automake autoconf bc pixman-devel coreutils make expect" \
	[qemu_dependencies]="libcap-devel libcap-ng-devel libattr-devel libcap-ng-devel librbd1-devel flex libfdt-devel ninja-build" \
	[kernel_dependencies]="elfutils-libelf-devel flex" \
	[crio_dependencies]="glibc-static libseccomp-devel libassuan-devel libgpg-error-devel device-mapper-libs util-linux gpgme-devel glib2-devel glibc-devel libselinux-devel pkgconfig" \
	[gperf_dependencies]="gcc-c++" \
	[bison_binary]="bison" \
	[build_tools]="python3 pkgconfig zlib-devel" \
	[os_tree]="ostree-devel" \
	[libudev-dev]="libgudev1-devel" \
	[metrics_dependencies]="jq" \
	[cri-containerd_dependencies]="libseccomp-devel" \
	[crudini]="crudini" \
	[procenv]="procenv" \
	[haveged]="haveged" \
	[libsystemd]="systemd-devel" \
	[redis]="redis" \
	[agent_shutdown_test]="tmux" \
	[virtiofsd_dependencies]="unzip" \
)

if [ "$(uname -m)" == "x86_64" ] ; then
	packages[qemu_dependencies]+=" libpmem-devel"
fi

if [ "$(uname -m)" == "ppc64le" ] || [ "$(uname -m)" == "s390x" ]; then
	packages[kata_containers_dependencies]+=" protobuf-compiler"
fi

if [ "$(uname -m)" == "s390x" ]; then
	packages[kernel_dependencies]+=" openssl openssl-devel"
fi

main()
{
	local setup_type="$1"
	[ -z "$setup_type" ] && die "need setup type"

	local pkgs_to_install
	local pkgs

	for pkgs in "${minimal_packages[@]}"; do
		pkgs_to_install+=" $pkgs"
	done

	if [ "$setup_type" = "default" ]; then
		for pkgs in "${packages[@]}"; do
			info "The following package will be installed: $pkgs"
			pkgs_to_install+=" $pkgs"
		done
	fi

	chronic sudo -E yum -y install $pkgs_to_install

	[ "$setup_type" = "minimal" ] && exit 0

	if [ "$KATA_KSM_THROTTLER" == "yes" ]; then
		echo "Install ${KATA_KSM_THROTTLER_JOB}"
		sudo -E yum install ${KATA_KSM_THROTTLER_JOB}
	fi
}

main "$@"
