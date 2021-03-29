#!/usr/bin/env bats
#
# Copyright (c) 2020 Ant Group
#
# SPDX-License-Identifier: Apache-2.0
#

load "${BATS_TEST_DIRNAME}/../../.ci/lib.sh"
load "${BATS_TEST_DIRNAME}/../../lib/common.bash"

setup() {
	export KUBECONFIG="$HOME/.kube/config"
	pod_name="pod-oom"
	get_pod_config_dir
}

@test "Test OOM events for pods" {
	wait_time=60
	sleep_time=5

	# Create pod
	kubectl create -f "${pod_config_dir}/pod-oom.yaml"

	# Check pod creation
	kubectl wait --for=condition=Ready pod "$pod_name"

	# Check if OOMKilled
	cmd="kubectl get pods "$pod_name" -o yaml | yq r - 'status.containerStatuses[0].state.terminated.reason' | grep OOMKilled"

	waitForProcess "$wait_time" "$sleep_time" "$cmd"
}

teardown() {
	# Debugging information
	kubectl describe "pod/$pod_name"
	kubectl get "pod/$pod_name" -o yaml

	kubectl delete pod "$pod_name"
}
