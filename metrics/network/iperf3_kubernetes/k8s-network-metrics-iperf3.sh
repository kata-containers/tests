#!/bin/bash
#
# Copyright (c) 2021 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#
# This test measures the following network essentials:
# - bandwith simplex
#
# These metrics/results will be got from the interconnection between
# a client and a server using iperf3 tool.
# The following cases are covered:
#
# case 1:
#  container-server <----> container-client
#
# case 2"
#  container-server <----> host-client

set -e

SCRIPT_PATH=$(dirname "$(readlink -f "$0")")

source "${SCRIPT_PATH}/../../../.ci/lib.sh"
source "${SCRIPT_PATH}/../../lib/common.bash"
test_repo="${test_repo:-github.com/kata-containers/tests}"
iperf_file=$(mktemp iperfresults.XXXXXXXXXX)

function remove_tmp_file() {
	rm -rf "${iperf_file}"
}

trap remove_tmp_file EXIT

function iperf3_bandwidth() {
	local TEST_NAME="network iperf3 bandwidth"
	cmds=("bc" "jq")
	check_cmds "${cmds[@]}"

	# Check no processes are left behind
	check_processes

	# Start kubernetes
	start_kubernetes

	export KUBECONFIG="$HOME/.kube/config"
	local service="iperf3-server"
	local deployment="iperf3-server-deployment"

	wait_time=20
	sleep_time=2

	# Create deployment
	kubectl create -f "${SCRIPT_PATH}/runtimeclass_workloads/iperf3-deployment.yaml"

	# Check deployment creation
	local cmd="kubectl wait --for=condition=Available deployment/${deployment}"
	waitForProcess "$wait_time" "$sleep_time" "$cmd"

	# Create DaemonSet
	kubectl create -f "${SCRIPT_PATH}/runtimeclass_workloads/iperf3-daemonset.yaml"

	# Expose deployment
	kubectl expose deployment/"${deployment}"

	# Get the names of the server pod
	local server_pod_name=$(kubectl get pods -o name | grep server | cut -d '/' -f2)

	# Verify the server pod is working
	local cmd="kubectl get pod $server_pod_name -o yaml | grep 'phase: Running'"
	waitForProcess "$wait_time" "$sleep_time" "$cmd"

	# Get the names of client pod
	local client_pod_name=$(kubectl get pods -o name | grep client | cut -d '/' -f2)

	# Verify the client pod is working
	local cmd="kubectl get pod $client_pod_name -o yaml | grep 'phase: Running'"
	waitForProcess "$wait_time" "$sleep_time" "$cmd"

	# Get the ip address of the server pod
	local server_ip_add=$(kubectl get pod "$server_pod_name" -o jsonpath='{.status.podIP}')

	metrics_json_init

	# Start server
	local transmit_timeout="30"

	kubectl exec -ti "$client_pod_name" -- sh -c "iperf3 -J -c ${server_ip_add} -t ${transmit_timeout}" | jq '.end.sum_received.bits_per_second' > "${iperf_file}"
	result=$(cat "${iperf_file}")

	local json="$(cat << EOF
	{
		"jitter": {
			"Result" : "$result",
			"Units" : "bits per second"
		}
	}
EOF
)"

	metrics_json_add_array_element "$json"
	metrics_json_end_array "Results"

	metrics_json_save

	kubectl delete deployment "$deployment"
	kubectl delete service "$deployment"
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

iperf3_bandwidth
