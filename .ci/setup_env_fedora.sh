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
TEST_CGROUPSV2="${TEST_CGROUPSV2:-false}"

if [ "${TEST_CGROUPSV2}" == "true" ]; then
	echo "Install podman"
	version=$(get_test_version "externals.podman.version")
	sudo -E dnf -y install podman-"${version}"
fi

declare -A minimal_packages=( \
	[spell-check]="hunspell hunspell-en-GB hunspell-en-US pandoc" \
	[xml_validator]="libxml2" \
	[yaml_validator]="yamllint" \
)

declare -A packages=( \
	[general_dependencies]="dnf-plugins-core python pkgconfig util-linux libgpg-error-devel" \
	[kata_containers_dependencies]="libtool automake autoconf bc pixman numactl-libs" \
	[qemu_dependencies]="libcap-devel libattr-devel libcap-ng-devel zlib-devel pixman-devel librbd-devel libpmem-devel" \
	[kernel_dependencies]="elfutils-libelf-devel flex" \
	[crio_dependencies]="btrfs-progs-devel device-mapper-devel glib2-devel glibc-devel glibc-static gpgme-devel libassuan-devel libseccomp-devel libselinux-devel" \
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

	sudo -E dnf -y install $pkgs_to_install

	[ "$setup_type" = "minimal" ] && exit 0

	echo "Install kata containers dependencies"
	sudo -E dnf -y groupinstall "Development tools"

	if [ "$KATA_KSM_THROTTLER" == "yes" ]; then
		echo "Install ${KATA_KSM_THROTTLER_JOB}"
		sudo -E dnf -y install ${KATA_KSM_THROTTLER_JOB}
	fi
}

main "$@"
