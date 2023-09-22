#!/bin/bash
# Copyright (c) 2022 Red Hat
#
# SPDX-License-Identifier: Apache-2.0
#
# This is a thin wrapper to call the confidential containers related tests.
#
set -e

script_dir=$(dirname "$(readlink -f "$0")")
cidir="${script_dir}/../../../.ci"
source "${cidir}/lib.sh"

main() {
	# Ensure nydus is installed and configured
	if [ "${IMAGE_OFFLOAD_TO_GUEST}" = "yes" ]; then
		info "Install nydus-snapshotter"
		bash -f "${cidir}/install_nydus_snapshotter.sh"
		bash -f "${cidir}/containerd_nydus_setup.sh"
	fi

	# Ensure bats is installed.
	${cidir}/install_bats.sh >/dev/null
	bats ${script_dir}/agent_image.bats \
		${script_dir}/agent_api.bats
}

main $@
