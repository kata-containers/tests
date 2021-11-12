#!/bin/bash
#
# Copyright (c) 2018-2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -e

cidir=$(dirname "$0")
source /etc/os-release || source /usr/lib/os-release
source "${cidir}/lib.sh"
echo "Install chronic"
sudo -E dnf -y install moreutils

declare -A minimal_packages=( \
	[spell-check]="hunspell hunspell-en-GB hunspell-en-US pandoc" \
	[xml_validator]="libxml2" \
	[yaml_validator]="yamllint" \
)

declare -A packages=( \
	[general_dependencies]="dnf-plugins-core python pkgconfig util-linux libgpg-error-devel which expect" \
	[kata_containers_dependencies]="libtool automake autoconf bc pixman numactl-libs" \
	[qemu_dependencies]="libcap-devel libattr-devel libcap-ng-devel zlib-devel pixman-devel librbd-devel ninja-build" \
	[kernel_dependencies]="elfutils-libelf-devel flex" \
	[crio_dependencies]="btrfs-progs-devel device-mapper-devel glib2-devel glibc-devel glibc-static gpgme-devel libassuan-devel libseccomp-devel libselinux-devel" \
	[gperf_dependencies]="gcc-c++" \
	[bison_binary]="bison" \
	[os_tree]="ostree-devel" \
	[metrics_dependencies]="jq" \
	[cri-containerd_dependencies]="libseccomp-devel btrfs-progs-devel libseccomp-static" \
	[crudini]="crudini" \
	[procenv]="procenv" \
	[haveged]="haveged" \
	[libsystemd]="systemd-devel" \
	[redis]="redis" \
	[versionlock]="python3-dnf-plugin-versionlock" \
	[agent_shutdown_test]="tmux" \
	[vfio_test]="pciutils driverctl" \
)

if [ "$(uname -m)" == "x86_64" ] || ([ "$(uname -m)" == "ppc64le" ] && [ "${VERSION_ID}" -ge "32" ]); then
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
		info "The following package will be installed: $pkgs"
		pkgs_to_install+=" $pkgs"
	done

	if [ "$setup_type" = "default" ]; then
		for pkgs in "${packages[@]}"; do
			info "The following package will be installed: $pkgs"
			pkgs_to_install+=" $pkgs"
		done
	fi

	chronic sudo -E dnf -y install $pkgs_to_install

	[ "$setup_type" = "minimal" ] && exit 0

	echo "Install kata containers dependencies"
	chronic sudo -E dnf -y groupinstall "Development tools"

	if [ "$KATA_KSM_THROTTLER" == "yes" ]; then
		echo "Install ${KATA_KSM_THROTTLER_JOB}"
		chronic sudo -E dnf -y install ${KATA_KSM_THROTTLER_JOB}
	fi
}

main "$@"
