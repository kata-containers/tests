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
arch=$("${cidir}"/kata-arch.sh -d)

echo "Install chronic"
sudo -E dnf -y install moreutils

declare -A minimal_packages=( \
	[spell-check]="hunspell hunspell-en-GB hunspell-en-US pandoc" \
	[xml_validator]="libxml2" \
	[yaml_validator]="yamllint" \
)

declare -A packages=( \
	[bison_binary]="bison" \
	[cri-containerd_dependencies]="btrfs-progs-devel libseccomp-devel libseccomp-static" \
	[crio_dependencies]="btrfs-progs-devel device-mapper-devel glibc-devel glibc-static glib2-devel gpgme-devel libassuan-devel libseccomp-devel libselinux-devel" \
	[crudini]="crudini" \
	[general_dependencies]="dnf-plugins-core libgpg-error-devel pkgconfig python util-linux xfsprogs" \
	[gnu_parallel]="parallel" \
	[haveged]="haveged" \
	[kata_containers_dependencies]="autoconf automake bc libtool numactl-libs pixman" \
	[kernel_dependencies]="elfutils-libelf-devel flex" \
	[libsystemd]="systemd-devel" \
	[metrics_dependencies]="jq" \
	[os_tree]="ostree-devel" \
	[procenv]="procenv" \
	[qemu_dependencies]="libattr-devel libcap-devel libcap-ng-devel librbd-devel libpmem-devel pixman-devel zlib-devel libselinux-devel libffi-devel libmount-devel libblkid-devel" \
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

	chronic sudo -E dnf -y install $pkgs_to_install

	[ "$setup_type" = "minimal" ] && exit 0

	echo "Install kata containers dependencies"
	chronic sudo -E dnf -y groupinstall "Development tools"

	if [ "$KATA_KSM_THROTTLER" == "yes" ]; then
		echo "Install ${KATA_KSM_THROTTLER_JOB}"
		chronic sudo -E dnf -y install ${KATA_KSM_THROTTLER_JOB}
	fi

	if [ "${TEST_CGROUPSV2}" == "true" ]; then
		echo "Install podman dependencies"
		sudo dnf -y builddep podman
		dnf deplist podman --archlist "${arch}",noarch | awk '/provider:/ {print $2}' | sort -u | xargs sudo -E dnf -y install
        	echo "Install podman"
        	version=$(get_test_version "externals.podman.version")
		podman_repo="github.com/containers/libpod"
		go get -d "${podman_repo}" || true
		pushd "${GOPATH}/src/${podman_repo}"
		git checkout v"${version}"
		make BUILDTAGS="selinux seccomp"
		sudo -E PATH=$PATH make install
		popd
	fi
}

main "$@"
