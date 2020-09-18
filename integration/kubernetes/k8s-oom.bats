#!/usr/bin/env bats
#
# Copyright (c) 2020 Ant Group
#
# SPDX-License-Identifier: Apache-2.0
#

load "${BATS_TEST_DIRNAME}/../../.ci/lib.sh"
load "${BATS_TEST_DIRNAME}/../../lib/common.bash"
issue="https://github.com/kata-containers/tests/issues/2859"

setup() {
	export KUBECONFIG="$HOME/.kube/config"
	pod_name="pod-oom"
	get_pod_config_dir
}

@test "Test OOM events for pods" {
	if [ "$CI_JOB" == "CRIO_K8S" ]; then
		skip "test not working on CRI-O, see: ${issue}"
	fi

	wait_time=20
	sleep_time=2

	# Create pod
	kubectl create -f "${pod_config_dir}/pod-oom.yaml"

	# Check pod creation
	kubectl wait --for=condition=Ready pod "$pod_name"

	# Check if OOMKilled
	cmd="kubectl get pods "$pod_name" -o yaml | yq r - 'status.containerStatuses[0].state.terminated.reason' | grep OOMKilled"

	waitForProcess "$wait_time" "$sleep_time" "$cmd"
}

teardown() {
	if [ "$CI_JOB" == "CRIO_K8S" ]; then
		skip "test not working on CRI-O, see: ${issue}"
	fi
	kubectl delete pod "$pod_name"
}
