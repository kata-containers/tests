#!/bin/bash
#
# Copyright (c) 2017-2020 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail

cidir=$(dirname "$0")
tag="${1:-""}"
source /etc/os-release || source /usr/lib/os-release
source "${cidir}/lib.sh"
KATA_HYPERVISOR="${KATA_HYPERVISOR:-qemu}"
experimental_qemu="${experimental_qemu:-false}"
TEST_CGROUPSV2="${TEST_CGROUPSV2:-false}"

echo "Install Kata Containers Image"
echo "rust image is default for Kata 2.0"
"${cidir}/install_kata_image.sh" "${tag}"

echo "Install Kata Containers Kernel"
"${cidir}/install_kata_kernel.sh" "${tag}"

echo "Install runtime"
"${cidir}/install_runtime.sh" "${tag}"

case "${KATA_HYPERVISOR}" in
	"cloud-hypervisor")
		"${cidir}/install_cloud_hypervisor.sh"
		;;
	"firecracker")
		"${cidir}/install_firecracker.sh"
		;;
	"qemu")
		# We assume qemu is installed by the base distro setup
		;;
	*)
		die "${KATA_HYPERVISOR} not supported for CI install"
		;;
esac

if [ "${TEST_CGROUPSV2}" == "true" ]; then
	echo "Configure podman with kata"
	"${cidir}/configure_podman_for_kata.sh"
fi
