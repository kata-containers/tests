#!/bin/bash
#
# Copyright (c) 2019 IBM
#
# SPDX-License-Identifier: Apache-2.0
#

set -e

source "${cidir}/lib.sh"

CURRENT_QEMU_VERSION=$(get_version "assets.hypervisor.qemu.version")
PACKAGED_QEMU="qemu"

[ "$ID" == "ubuntu" ] || die "Unsupported distro: $ID"

get_packaged_qemu_version() {
	if [ "$ID" == "ubuntu" ]; then
		sudo apt-get update > /dev/null
		qemu_version=$(apt-cache madison $PACKAGED_QEMU \
		| awk '{print $3}' | cut -d':' -f2 | cut -d'+' -f1 | head -n 1 )
	fi

	if [ -z "$qemu_version" ]; then
		die "unknown qemu version"
	else
		echo "${qemu_version}"
	fi
}

install_packaged_qemu() {
	sudo apt install -y "$PACKAGED_QEMU"
}
