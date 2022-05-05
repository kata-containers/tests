#!/bin/bash
#
# Copyright (c) 2022 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

set -e
set -x

SCRIPT_PATH=$(dirname "$(readlink -f "$0")")

source "${SCRIPT_PATH}/../../../.ci/lib.sh"
source "${SCRIPT_PATH}/../../lib/common.bash"
test_repo="${test_repo:-github.com/kata-containers/tests}"
TEST_NAME="${TEST_NAME:-cassandra}"
cassandra_file=$(mktemp cassandraresults.XXXXXXXXXX)

function remove_tmp_file() {
	rm -rf "${cassandra_file}"
}

trap remove_tmp_file EXIT

function cassandra_write_test() {
	cassandra_start
	export pod_name="cassandra-0"
	export write_cmd="/usr/local/apache-cassandra-3.11.2/tools/bin/cassandra-stress write n=1000000 cl=one -mode native cql3 -schema keyspace="keyspace1" -pop seq=1..1000000 -node cassandra"
 	number_of_retries="50"
	for _ in $(seq 1 "$number_of_retries"); do
		if kubectl exec -i cassandra-0 -- sh -c 'nodetool status' | grep Up; then
			ok="1"
 			break;
		fi
 		sleep 1
	done
	# This is needed to wait that cassandra is up
	sleep 30
	kubectl exec -i cassandra-0 -- sh -c "$write_cmd" > "${cassandra_file}"
	op_rate=$(cat "${cassandra_file}" | grep -e "Op rate" | cut -d':' -f2  | sed -e 's/^[ \t]*//' | cut -d ' ' -f1)
	metrics_json_init
	# Save configuration
	metrics_json_start_array

	local json="$(cat << EOF
	{
		"Op rate": {
			"Result" : "$op_rate",
			"Units" : "op/s"
		}
	}
EOF
)"

	metrics_json_add_array_element "$json"
	metrics_json_end_array "Results"

	metrics_json_save
	cassandra_cleanup
}

function cassandra_start() {
	cmds=("bc" "jq")
	check_cmds "${cmds[@]}"

	# Check no processes are left behind
	check_processes

	# Start kubernetes
	start_kubernetes

	export KUBECONFIG="$HOME/.kube/config"
	export service_name="cassandra"
	export app_name="cassandra"

	wait_time=20
 	sleep_time=2

	# Create service
	kubectl create -f "${SCRIPT_PATH}/runtimeclass_workloads/cassandra-service.yaml"

	# Check service
	kubectl get svc | grep "$service_name"

	# Create local volumes
	kubectl create -f "${SCRIPT_PATH}/runtimeclass_workloads/local-volumes.yaml"

	# Create statefulset
	kubectl create -f "${SCRIPT_PATH}/runtimeclass_workloads/cassandra-statefulset.yaml"

	cmd="kubectl rollout status --watch --timeout=120s statefulset/$app_name"
 	waitForProcess "$wait_time" "$sleep_time" "$cmd"

	# Check pods are running
	cmd="kubectl get pods -o jsonpath='{.items[*].status.phase}' | grep Running"
	waitForProcess "$wait_time" "$sleep_time" "$cmd"
}

function cassandra_cleanup() {
	kubectl delete svc "$service_name"
	kubectl delete pod -l app="$app_name"
	end_kubernetes
	check_processes
}

function start_kubernetes() {
	info "Start k8s"
	pushd "${GOPATH}/src/${test_repo}/integration/kubernetes"
	bash ./init.sh
	popd
}

function end_kubernetes() {
	info "End k8s"
	pushd "${GOPATH}/src/${test_repo}/integration/kubernetes"
	bash ./cleanup_env.sh
	popd
}

function main() {
	init_env
	cassandra_write_test
}

main "$@"
