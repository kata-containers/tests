#!/bin/bash
#
# Copyright (c) 2019-2020 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

cidir=$(dirname "$0")
source "${cidir}/lib.sh"

main() {
	build_static_artifact_and_install "rootfs-image"
	build_static_artifact_and_install "rootfs-initrd"

	# Build and install an image for the guest AppArmor
	build_install_apparmor_image
}

main
