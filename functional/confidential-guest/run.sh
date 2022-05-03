#!/bin/bash
# Copyright (c) 2022 Red Hat
#
# SPDX-License-Identifier: Apache-2.0
#
# Entry point script to run the confidential guest tests. It run the tests
# implemented for the specific TEE (Trusted Execution Environment), which
# should be indicated in the $TEE_TYPE environment variable.

[ -z "${DEBUG:-}" ] || set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

script_dir="$(dirname $0)"
source "${script_dir}/../../lib/common.bash"

TEE_TYPE="${TEE_TYPE:-tdx}"

main() {
	case "$TEE_TYPE" in
		tdx)
			bash "${script_dir}/tdx/run.sh" ;;
		*)
			warn "Not implemented tests for TEE type: $TEE_TYPE. Skipping."
			return 0
			;;
	esac
}

main $@
