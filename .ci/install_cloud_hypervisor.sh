#!/bin/bash
#
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

cidir=$(dirname "$0")
source "${cidir}/lib.sh"

# Whether build for confidential containers or not.
KATA_BUILD_CC="${KATA_BUILD_CC:-no}"

main() {
	build_static_artifact_and_install "cloud-hypervisor"

	[ "${KATA_BUILD_CC}" == "yes" ] || \
		sudo ln -sf /opt/kata/bin/cloud-hypervisor /usr/bin/cloud-hypervisor
}

main "$@"