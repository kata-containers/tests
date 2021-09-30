#!/bin/bash
#
# Copyright (c) 2021 IBM Corp.
#
# SPDX-License-Identifier: Apache-2.0

set -o errexit
source "$(dirname "${0}")/../lib/common.bash"

declare -A package_managers
package_managers=([debian]=apt [fedora]=dnf [suse]=zypper)

info "Install gcc"
for distro in "${!package_managers[@]}"; do
	if grep -Eq "\<${distro}\>" /etc/os-release 2> /dev/null; then
		sudo "${package_managers["${distro}"]}" install -y gcc
		exit 0
	fi
done

die "Failed to install gcc"
