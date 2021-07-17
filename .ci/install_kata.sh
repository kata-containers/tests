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
osbuilder_distro="$ID" "${cidir}/install_kata_image.sh" "${tag}"

echo "Install Kata Containers Kernel"
"${cidir}/install_kata_kernel.sh" "${tag}"

install_qemu(){
	echo "Installing qemu"
	if [ "$experimental_qemu" == "true" ]; then
		echo "Install experimental Qemu"
		"${cidir}/install_qemu_experimental.sh"
	else
		"${cidir}/install_qemu.sh"
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
