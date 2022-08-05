#!/bin/bash
#
# Copyright (c) 2022 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

set -e

# General env
SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_PATH}/../../lib/common.bash"
CI_JOB="${CI_JOB:-}"
TEST_REPO="${test_repo:-github.com/kata-containers/tests}"
FIO_PATH="${GOPATH}/src/${TEST_REPO}/metrics/storage/fio-k8s"
TEST_NAME="${TEST_NAME:-fio}"

function main() {
	cmds=("bc" "jq")
	check_cmds "${cmds[@]}"
	check_processes
	init_env

	if [ -z "${CI_JOB}" ]; then
		# Start kubernetes
		start_kubernetes
	fi
	export KUBECONFIG="$HOME/.kube/config"

	pushd "${FIO_PATH}"
		echo "INFO: Running K8S FIO test"
		make test-ci
	popd

	test_result_file="${FIO_PATH}/cmd/fiotest/test-results/kata/randrw-sync.job/output.json"

	metrics_json_init
	local read_io=$(cat $test_result_file | grep io_bytes | head -1 | sed 's/[[:blank:]]//g' | cut -f2 -d ':' | cut -f1 -d ',')
	local read_bw=$(cat $test_result_file | grep bw_bytes | head -1 | sed 's/[[:blank:]]//g' | cut -f2 -d ':' | cut -f1 -d ',')

	metrics_json_start_array
	local json="$(cat << EOF
	{
		"readio": {
			"Result" : $read_io,
			"Units" : "bytes"
		},
		"readbw": {
			"Result" : $read_bw,
			"Units" : "bytes/sec"
		}
	}
EOF
)"
	metrics_json_add_array_element "$json"
	metrics_json_end_array "Results"
	metrics_json_save

	if [ -z "${CI_JOB}" ]; then
		end_kubernetes
		check_processes
	fi
}

main "$@"
