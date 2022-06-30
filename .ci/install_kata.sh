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
KATA_BUILD_KERNEL_TYPE="${KATA_BUILD_KERNEL_TYPE:-vanilla}"
KATA_BUILD_QEMU_TYPE="${KATA_BUILD_QEMU_TYPE:-vanilla}"
KATA_HYPERVISOR="${KATA_HYPERVISOR:-qemu}"
experimental_qemu="${experimental_qemu:-false}"
TEE_TYPE="${TEE_TYPE:-}"

if [ -n "${TEE_TYPE}" ]; then
	echo "Install with TEE type: ${TEE_TYPE}"
fi

if [ "${TEE_TYPE:-}" == "tdx" ]; then
	KATA_BUILD_KERNEL_TYPE="${KATA_BUILD_KERNEL_TYPE:-tdx}"
	KATA_BUILD_QEMU_TYPE="${KATA_BUILD_QEMU_TYPE:-tdx}"
fi

if [ "${TEE_TYPE:-}" == "sev" ]; then
	KATA_BUILD_KERNEL_TYPE=sev
fi

echo "Install Kata Containers Image"
echo "rust image is default for Kata 2.0"
"${cidir}/install_kata_image.sh" "${tag}"

echo "Install Kata Containers Kernel"
"${cidir}/install_kata_kernel.sh" -t "${KATA_BUILD_KERNEL_TYPE}"

install_qemu(){
	echo "Installing qemu"
	if [ "$experimental_qemu" == "true" ]; then
		echo "Install experimental Qemu"
		"${cidir}/install_qemu_experimental.sh"
	else
		"${cidir}/install_qemu.sh" -t "${KATA_BUILD_QEMU_TYPE}"
	fi
}

echo "Install runtime"
"${cidir}/install_runtime.sh" "${tag}"

case "${KATA_HYPERVISOR}" in
	"cloud-hypervisor")
		"${cidir}/install_cloud_hypervisor.sh"
		echo "Installing experimental_qemu to install virtiofsd"
		install_qemu
		;;
	"firecracker")
		"${cidir}/install_firecracker.sh"
		;;
	"qemu")
		install_qemu
		;;
	*)
		die "${KATA_HYPERVISOR} not supported for CI install"
		;;
esac

kata-runtime kata-env
echo "Kata config:"
cat $(kata-runtime kata-env  --json | jq .Runtime.Config.Path -r)
