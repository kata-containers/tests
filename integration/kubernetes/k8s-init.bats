#!/usr/bin/env bats
#
# Copyright (c) 2020 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

load "${BATS_TEST_DIRNAME}/../../.ci/lib.sh"
load "${BATS_TEST_DIRNAME}/../../lib/common.bash"

setup() {
	export KUBECONFIG="$HOME/.kube/config"
	pod_name="test-init"
	get_pod_config_dir
}

@test "Test init containers" {
	# Create pod
	kubectl create -f "${pod_config_dir}/pod-init.yaml"

	# Check pod creation
	kubectl wait --for=condition=Ready pod "$pod_name"
	cmd="printenv"
	kubectl exec $pod_name -- sh -c $cmd | grep "HOSTNAME=$pod_name"
}

teardown() {
	kubectl delete pod "$pod_name"
}
