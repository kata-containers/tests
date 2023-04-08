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

arch=$("${cidir}"/kata-arch.sh -d)
go_arch=$("${cidir}"/kata-arch.sh -g)
TEST_INITRD="${TEST_INITRD:-no}"
KATA_BUILD_CC="${KATA_BUILD_CC:-no}"
TEE_TYPE="${TEE_TYPE:-}"

build_image_for_cc () {
	if [ "${TEST_INITRD}" == "yes" ]; then
		if [ "${TEE_TYPE}" != "sev" ] && [ "${TEE_TYPE}" != "snp" ]; then
		  die "SEV and SNP are the only TEE types that supports initrd"
		fi
		build_static_artifact_and_install "sev-rootfs-initrd"
	else
		[ "${osbuilder_distro:-ubuntu}" == "ubuntu" ] || \
			die "The only supported image for Confidential Containers is Ubuntu"

		if [ "${TEE_TYPE}" == "tdx" ] && [ "${KATA_HYPERVISOR}" == "qemu" ]; then
			# Cloud Hypervisor is still using `offline_fs_kbc`, so it has to
			# use the generic image.  QEMU, on the other hand, is using
			# `cc_kbc` and it requires the `tdx-rootfs-image`.
			build_static_artifact_and_install "tdx-rootfs-image"
		elif [ "${TEE_TYPE}" == "se" ]; then
			build_static_artifact_and_install "rootfs-initrd"
		else
			build_static_artifact_and_install "rootfs-image"
		fi
	fi
}

main() {
	if [ ${KATA_BUILD_CC} == "yes" ]; then
		build_image_for_cc
	else
		build_static_artifact_and_install "rootfs-image"
		build_static_artifact_and_install "rootfs-initrd"
	fi
}

main