#!/bin/bash
#
# Copyright (c) 2017-2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail

cidir=$(dirname "$0")
source /etc/os-release || source /usr/lib/os-release
source "${cidir}/lib.sh"

echo "Install kata-containers image"
ci_chronic "${cidir}/install_kata_image.sh"

echo "Install Kata Containers Kernel"
ci_chronic "${cidir}/install_kata_kernel.sh"

echo "Install Qemu"
ci_chronic "${cidir}/install_qemu.sh"

echo "Install shim"
ci_chronic "${cidir}/install_shim.sh"

echo "Install proxy"
ci_chronic "${cidir}/install_proxy.sh"

echo "Install runtime"
ci_chronic "${cidir}/install_runtime.sh"
