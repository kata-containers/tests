#!/usr/bin/env bats
#
# Copyright (c) 2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

load "${BATS_TEST_DIRNAME}/../../.ci/lib.sh"
load "${BATS_TEST_DIRNAME}/../../lib/common.bash"

setup() {
	export KUBECONFIG="$HOME/.kube/config"
	pod_name="test-env"
	get_pod_config_dir
}

@test "Environment variables" {
	wait_time=20
	sleep_time=2

	# Create pod
	kubectl create -f "${pod_config_dir}/pod-env.yaml"

	# Check pod creation
	cmd="kubectl wait --for=condition=Ready pod $pod_name"
	waitForProcess "$wait_time" "$sleep_time" "$cmd"

	# Print environment variables
	cmd="printenv"
	kubectl exec $pod_name -- sh -c $cmd | grep "MY_POD_NAME=$pod_name"
}

teardown() {
	kubectl delete pod "$pod_name"
	run check_pods
	echo "$output"
	[ "$status" -eq 0 ]
}
