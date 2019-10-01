#!/bin/bash
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

readonly script_dir=$(dirname $(readlink -f "$0"))
run_sh="${script_dir}/run.sh"
timeout=10m

main() {
	while read -r d; do
		timeout --foreground "${timeout}" "${run_sh}" "${d}"
	done < <(find "${script_dir}" -type d -name 'test_*')

}

main $*
