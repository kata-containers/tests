#!/bin/bash
#
# Copyright (c) 2021 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#
# This test measures the following network essentials:
# - bandwith simplex
# - jitter
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
TEST_NAME="${TEST_NAME:-IPerf}"

function remove_tmp_file() {
	rm -rf "${iperf_file}"
}

trap remove_tmp_file EXIT

function iperf3_bandwidth() {
	iperf3_start_deployment
	local TEST_NAME="network iperf3 bandwidth"
	metrics_json_init

	# Start server
	local transmit_timeout="30"

	kubectl exec -i "$client_pod_name" -- sh -c "iperf3 -J -c ${server_ip_add} -t ${transmit_timeout}" | jq '.end.sum_received.bits_per_second' > "${iperf_file}"
	result=$(cat "${iperf_file}")

	local json="$(cat << EOF
	{
		"bandwidth": {
			"Result" : $result,
			"Units" : "bits per second"
		}
	}
EOF
)"

	metrics_json_add_array_element "$json"
	metrics_json_end_array "Results"

	metrics_json_save
	iperf3_deployment_cleanup
}

function iperf3_utc_jitter() {
	iperf3_start_deployment
	local TEST_NAME="network iperf3 utc jitter"
	metrics_json_init

	# Start server
	local transmit_timeout="30"

	kubectl exec -i "$client_pod_name" -- sh -c "iperf3 -J -c ${server_ip_add} -u -t ${transmit_timeout}" | jq '.end.sum.jitter_ms' > "${iperf_file}"
	result=$(cat "${iperf_file}")

	local json="$(cat << EOF
	{
		"jitter": {
			"Result" : $result,
			"Units" : "ms"
		}
	}
EOF
)"

	metrics_json_add_array_element "$json"
	metrics_json_end_array "Results"

	metrics_json_save
	iperf3_deployment_cleanup
}

function cpu_metrics_iperf3() {
	cmd=("awk")
	check_cmds "${cmds[@]}"

	iperf3_start_deployment
	local TEST_NAME="cpu metrics running iperf3"

	# Start server
	local transmit_timeout="80"

	kubectl exec -i "$client_pod_name" -- sh -c "iperf3 -J -c ${server_ip_add} -t ${transmit_timeout}" | jq '.end.cpu_utilization_percent.host_total' > "${iperf_file}"
	result=$(cat "${iperf_file}")

	metrics_json_init

	local json="$(cat << EOF
	{
		"cpu utilization host total": {
			"Result" : $result,
			"Units"  : "percent"
		}
	}
EOF
)"

	metrics_json_add_array_element "$json"
	metrics_json_end_array "Results"

	metrics_json_save
	iperf3_deployment_cleanup
}

function iperf3_start_deployment() {
	cmds=("bc" "jq")
	check_cmds "${cmds[@]}"

	# Check no processes are left behind
	check_processes

	# Start kubernetes
	start_kubernetes

	export KUBECONFIG="$HOME/.kube/config"
	export service="iperf3-server"
	export deployment="iperf3-server-deployment"

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
	export server_pod_name=$(kubectl get pods -o name | grep server | cut -d '/' -f2)

	# Verify the server pod is working
	local cmd="kubectl get pod $server_pod_name -o yaml | grep 'phase: Running'"
	waitForProcess "$wait_time" "$sleep_time" "$cmd"

	# Get the names of client pod
	export client_pod_name=$(kubectl get pods -o name | grep client | cut -d '/' -f2)

	# Verify the client pod is working
	local cmd="kubectl get pod $client_pod_name -o yaml | grep 'phase: Running'"
	waitForProcess "$wait_time" "$sleep_time" "$cmd"

	# Get the ip address of the server pod
	export server_ip_add=$(kubectl get pod "$server_pod_name" -o jsonpath='{.status.podIP}')
}

function iperf3_deployment_cleanup() {
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

function help() {
echo "$(cat << EOF
Usage: $0 "[options]"
	Description:
		This script implements a number of network metrics
		using iperf3.

	Options:
		-a	Run all tests
		-b 	Run bandwidth tests
		-c	Run cpu metrics tests
		-h	Help
		-j	Run jitter tests
EOF
)"
}

function main() {
	init_env

	local OPTIND
	while getopts ":abcjh:" opt
	do
		case "$opt" in
		a)	# all tests
			test_bandwidth="1"
			test_jitter="1"
			;;
		b)	# bandwith test
			test_bandwith="1"
			;;
		c)
			# run cpu tests
			test_cpu="1"
			;;
		h)
			help
			exit 0;
			;;
		j)	# jitter tests
			test_jitter="1"
			;;
		:)
			echo "Missing argument for -$OPTARG";
			help
			exit 1;
			;;
		esac
	done
	shift $((OPTIND-1))

	[[ -z "$test_bandwith" ]] && \
	[[ -z "$test_jitter" ]] && \
	[[ -z "$test_cpu" ]] && \
		help && die "Must choose at least one test"

	if [ "$test_bandwith" == "1" ]; then
		iperf3_bandwidth
	fi

	if [ "$test_jitter" == "1" ]; then
		iperf3_jitter
	fi

	if [ "$test_cpu" == "1" ]; then
		cpu_metrics_iperf3
	fi
}

main "$@"
