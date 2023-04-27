#!/bin/bash
#
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o nounset
set -o pipefail

cidir=$(dirname "$0")
source "${cidir}/lib.sh"

main() {
	build_static_artifact_and_install "firecracker"
}

main "$@"
