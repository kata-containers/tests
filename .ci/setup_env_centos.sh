#!/bin/bash
#
# Copyright (c) 2018-2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -e

cidir=$(dirname "$0")
source "/etc/os-release" || "source /usr/lib/os-release"
source "${cidir}/lib.sh"

# Obtain CentOS version
if [ -f /etc/os-release ]; then
  centos_version=$(grep VERSION_ID /etc/os-release | cut -d '"' -f2)
else
  centos_version=$(grep VERSION_ID /usr/lib/os-release | cut -d '"' -f2)
fi

[ "$centos_version" == 8 ] || die "This script is for CentOS 8 only"

# Send error when a package is not available in the repositories
echo "skip_missing_names_on_install=0" | sudo tee -a /etc/yum.conf

# Ensure EPEL repository is configured
sudo -E dnf -y install epel-release

# Enable priority to CentOS Base repo in order to
# avoid perl updating issues
for repo_file_path in /etc/yum.repos.d/CentOS-Base.repo \
	/etc/yum.repos.d/CentOS-Linux-BaseOS.repo \
	/etc/yum.repos.d/CentOS-Stream-BaseOS.repo; do
	if [ -f "$repo_file_path" ]; then
		repo_file="$repo_file_path"
		break
	fi
done
[ -n "${repo_file:-}" ] || die "Unable to find the CentOS base repository file"
echo "priority=1" | sudo tee -a "$repo_file"

sudo -E dnf -y clean all

echo "Update repositories"
sudo -E dnf -y --nobest update

echo "Enable PowerTools repository"
sudo -E dnf install -y 'dnf-command(config-manager)'
sudo dnf config-manager --enable powertools

echo "Install chronic"
sudo -E dnf -y install moreutils

chronic sudo -E dnf install -y pkgconf-pkg-config

declare -A minimal_packages=( \
	[spell-check]="hunspell hunspell-en-GB hunspell-en-US pandoc" \
	[xml_validator]="libxml2" \
	[yaml_validator]="yamllint" \
)

declare -A packages=( \
	[kata_containers_dependencies]="libtool libtool-ltdl-devel device-mapper-persistent-data lvm2 libtool-ltdl" \
	[qemu_dependencies]="libcap-devel libcap-ng-devel libattr-devel libcap-ng-devel librbd1-devel flex libfdt-devel libpmem-devel ninja-build" \
	[kernel_dependencies]="elfutils-libelf-devel flex pkgconfig patch" \
	[crio_dependencies]="glibc-static libseccomp-devel libassuan-devel libgpg-error-devel util-linux libselinux-devel" \
	[gperf_dependencies]="gcc-c++" \
	[bison_binary]="bison" \
	[libgudev1-dev]="libgudev1-devel" \
	[general_dependencies]="gpgme-devel glib2-devel glibc-devel bzip2 m4 gettext-devel automake autoconf pixman-devel coreutils expect" \
	[build_tools]="python3 pkgconfig zlib-devel" \
	[ostree]="ostree-devel" \
	[metrics_dependencies]="bc jq" \
	[crudini]="crudini" \
	[procenv]="procenv" \
	[haveged]="haveged" \
	[libsystemd]="systemd-devel" \
	[redis]="redis" \
	[make]="make" \
	[agent_shutdown_test]="tmux" \
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

	# On centos:8 container image the installation of coreutils
	# conflicts with coreutils-single because they mutually
	# exclusive. Let's pass --allowerasing so that coreutils-single
	# is replaced.
	chronic sudo -E dnf -y install --allowerasing $pkgs_to_install

	[ "$setup_type" = "minimal" ] && exit 0

	if [ "$KATA_KSM_THROTTLER" == "yes" ]; then
		echo "Install ${KATA_KSM_THROTTLER_JOB}"
		chronic sudo -E dnf install ${KATA_KSM_THROTTLER_JOB}
	fi
}

main "$@"
