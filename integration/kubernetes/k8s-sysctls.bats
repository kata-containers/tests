#!/usr/bin/env bats
#
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

load "${BATS_TEST_DIRNAME}/../../.ci/lib.sh"
load "${BATS_TEST_DIRNAME}/../../lib/common.bash"
issue="https://github.com/kata-containers/tests/issues/3472"

setup() {
        if [ "$CI_JOB" == "CRIO_K8S" ]; then
                skip "test not working on CRI-O, see: ${issue}"
        fi

	export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
	pod_name="sysctl-test"
	get_pod_config_dir
}

@test "Setting sysctl" {
        if [ "$CI_JOB" == "CRIO_K8S" ]; then
                skip "test not working on CRI-O, see: ${issue}"
        fi

	# Create pod
	kubectl apply -f "${pod_config_dir}/pod-sysctl.yaml"

	# Check pod creation
	kubectl wait --for=condition=Ready --timeout=$timeout pod $pod_name

	# Check sysctl configuration
	cmd="cat /proc/sys/kernel/shm_rmid_forced"
	result=$(kubectl exec $pod_name -- sh -c "$cmd")
	[ "${result}" = 0 ]
}

teardown() {
        if [ "$CI_JOB" == "CRIO_K8S" ]; then
                skip "test not working on CRI-O, see: ${issue}"
        fi

	# Debugging information
	kubectl describe "pod/$pod_name"

	kubectl delete pod "$pod_name"
}
