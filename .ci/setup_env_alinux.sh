#!/bin/bash
#
# Copyright (c) 2022 Ant Group
#
# SPDX-License-Identifier: Apache-2.0
#
set -o errtrace
set -o nounset
set -o pipefail

[ -n "${DEBUG:-}" ] && set -o xtrace

cidir=$(dirname "$0")
source "/etc/os-release" || "source /usr/lib/os-release"
source "${cidir}/lib.sh"

# Obtain AlibabaCloud Linux version
# Either /etc/os-release or /usr/lib/os-release is source´ed
# so that VERSION_ID is already exported.
[ "$VERSION_ID" -ge 3 ] || die "This script is for alinux 3 and above only"

# Send error when a package is not available in the repositories
if [ "$(tail -1 /etc/dnf/dnf.conf | tr -d '\n')" != "skip_missing_names_on_install=0" ]; then
	echo "skip_missing_names_on_install=0" | sudo tee -a /etc/dnf/dnf.conf
fi

# Ensure EPEL repository is configured
sudo -E dnf -y install epel-release

# Enable priority to AlibabaCloud Linux Base repo in order to
# avoid perl updating issues
[ -f "/etc/yum.repos.d/AliYun.repo" ] && repo_file="/etc/yum.repos.d/AliYun.repo"

[ -n "${repo_file:-}" ] || die "Unable to find the AlibabaCloud Linux base repository file"

if [ "$(tail -1 ${repo_file} | tr -d '\n')" != "priority=1" ]; then
	echo "priority=1" | sudo tee -a "$repo_file"
fi

sudo -E dnf -y clean all

echo "Update repositories"
sudo -E dnf -y --nobest update

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
	[haveged]="haveged" \
	[libsystemd]="systemd-devel" \
	[redis]="redis" \
	[make]="make" \
	[agent_shutdown_test]="tmux" \
	[virtiofsd_dependencies]="unzip" \
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

	# On AlibabaCloud Linux:3 container image the installation of coreutils
	# conflicts with coreutils-single because they mutually
	# exclusive. Let's pass --allowerasing so that coreutils-single
	# is replaced.
	chronic sudo -E dnf -y install --allowerasing $pkgs_to_install
}

main "$@"
