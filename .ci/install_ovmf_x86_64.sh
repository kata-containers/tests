#!/bin/bash
# Copyright 2022 Advanced Micro Devices, Inc.
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
	build_static_artifact_and_install x86_64-ovmf
}

main "$@"
