#!/usr/bin/env bats
#
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

load "${BATS_TEST_DIRNAME}/../../.ci/lib.sh"
load "${BATS_TEST_DIRNAME}/../../lib/common.bash"
issue="https://github.com/kata-containers/tests/issues/2574"

setup() {
	skip "test not working - see: ${issue}"
	export KUBECONFIG="$HOME/.kube/config"
	pod_name="sharevol-kata"
	get_pod_config_dir
}

@test "Empty dir volumes" {
	skip "test not working - see: ${issue}"
	# Create the pod
	kubectl create -f "${pod_config_dir}/pod-empty-dir.yaml"

	# Check pod creation
	kubectl wait --for=condition=Ready pod "$pod_name"

	# Check volume mounts
	cmd="mount | grep cache"
	kubectl exec $pod_name -- sh -c "$cmd" | grep "/tmp/cache type tmpfs"
}

teardown() {
	skip "test not working - see: ${issue}"
	kubectl delete pod "$pod_name"
	run check_pods
	echo "$output"
	[ "$status" -eq 0 ]
}
