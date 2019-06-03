#!/usr/bin/env bats
#
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

load "${BATS_TEST_DIRNAME}/../../.ci/lib.sh"
load "${BATS_TEST_DIRNAME}/../../lib/common.bash"

setup() {
	export KUBECONFIG="$HOME/.kube/config"
	get_pod_config_dir
}

@test "Health checks" {
	pod_name="hctest"
	bad_pod_name="badhctest"
	wait_time=120
	sleep_time=2

	# Create pod
	kubectl create -f "${pod_config_dir}/pod-health.yaml"

	# Check pod creation
	kubectl wait --for=condition=Ready --timeout="$wait_time"s pod "$pod_name"

	# Check pod status
	cmd="kubectl describe pod $pod_name | grep 'Started container'"
	waitForProcess "$wait_time" "$sleep_time" "$cmd"

	# Create a bad pod
	kubectl create -f "${pod_config_dir}/pod-bad-health.yaml"

	# Check pod creation
	kubectl wait --for=condition=Ready --timeout="$wait_time"s pod "$pod_name"

	# Check bad pod status
	cmd="kubectl describe pod $bad_pod_name | grep Unhealthy"
	waitForProcess "$wait_time" "$sleep_time" "$cmd"
}

teardown() {
	kubectl delete pod "$pod_name" "$bad_pod_name"
}
