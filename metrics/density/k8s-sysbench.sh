#!/bin/bash
#
# Copyright (c) 2022 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

set -o errexit
set -o nounset
set -o pipefail
set -x

SCRIPT_PATH=$(dirname "$(readlink -f "$0")")

source "${SCRIPT_PATH}/../../.ci/lib.sh"
source "${SCRIPT_PATH}/../lib/common.bash"
sysbench_file=$(mktemp sysbenchresults.XXXXXXXXXX)
TEST_NAME="${TEST_NAME:-sysbench}"
CI_JOB="${CI_JOB:-}"
IMAGE="docker.io/library/local-sysbench:latest"
DOCKERFILE="${SCRIPT_PATH}/sysbench-dockerfile/Dockerfile"

function remove_tmp_file() {
	rm -rf "${sysbench_file}"
}

trap remove_tmp_file EXIT

function sysbench_memory() {
	kubectl exec -i "$pod_name" -- sh -c "sysbench memory --threads=2 run" > "${sysbench_file}"
	metrics_json_init
	local memory_latency_sum=$(cat "$sysbench_file" | grep sum | cut -f2 -d':' | sed 's/[[:blank:]]//g')
	metrics_json_start_array
	local json="$(cat << EOF
	{
		"memorylatencysum": {
			"Result" : $memory_latency_sum,
			"Units" : "ms"
		}
	}
EOF
)"
	metrics_json_add_array_element "$json"
	metrics_json_end_array "Results"
	metrics_json_save
}

function sysbench_start_deployment() {
	cmds=("bc" "jq")
	check_cmds "${cmds[@]}"

	# Check no processes are left behind
	check_processes

	if [ -z "${CI_JOB}" ]; then
		# Start kubernetes
		start_kubernetes
	fi

	export KUBECONFIG="$HOME/.kube/config"
	export pod_name="test-sysbench"

	kubectl create -f "${SCRIPT_PATH}/runtimeclass_workloads/sysbench-pod.yaml"
	kubectl wait --for=condition=Ready --timeout=120s pod "$pod_name"

}

function sysbench_cleanup() {
	kubectl delete pod "$pod_name"
	if [ -z "${CI_JOB}" ]; then
		end_kubernetes
		check_processes
	fi
}

function main() {
	init_env
	sysbench_start_deployment
	sysbench_memory
	sysbench_cleanup
}

main "$@"
