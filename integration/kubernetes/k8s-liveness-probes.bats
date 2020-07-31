#!/usr/bin/env bats
#
# Copyright (c) 2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

load "${BATS_TEST_DIRNAME}/../../.ci/lib.sh"
load "${BATS_TEST_DIRNAME}/../../lib/common.bash"
issue="https://github.com/kata-containers/tests/issues/2574"

setup() {
	[ "${CI_JOB}" == "CRIO_K8S" ] && skip "test not working - see: ${issue}"
	export KUBECONFIG="$HOME/.kube/config"
	sleep_liveness=20

	get_pod_config_dir
}

@test "Liveness probe" {
    BASH_XTRACEFD=3
    set -x
	[ "${CI_JOB}" == "CRIO_K8S" ] && skip "test not working - see: ${issue}"
	pod_name="liveness-exec"

	# Create pod
	kubectl create -f "${pod_config_dir}/pod-liveness.yaml"

	# Check pod creation
	kubectl wait --for=condition=Ready pod "$pod_name"

	# Check liveness probe returns a success code
	kubectl describe pod "$pod_name" | grep -E "Liveness|#success=1"

	# Sleep necessary to check liveness probe returns a failure code
	sleep "$sleep_liveness"
	kubectl describe pod "$pod_name" | grep "Liveness probe failed"
}

@test "Liveness http probe" {
	[ "${CI_JOB}" == "CRIO_K8S" ] && skip "test not working - see: ${issue}"
	pod_name="liveness-http"

	# Create pod
	kubectl create -f "${pod_config_dir}/pod-http-liveness.yaml"

	# Check pod creation
	kubectl wait --for=condition=Ready pod "$pod_name"

	# Check liveness probe returns a success code
	kubectl describe pod "$pod_name" | grep -E "Liveness|#success=1"

	# Sleep necessary to check liveness probe returns a failure code
	sleep "$sleep_liveness"
	kubectl describe pod "$pod_name" | grep "Started container"
}


@test "Liveness tcp probe" {
	[ "${CI_JOB}" == "CRIO_K8S" ] && skip "test not working - see: ${issue}"
	pod_name="tcptest"

	# Create pod
	kubectl create -f "${pod_config_dir}/pod-tcp-liveness.yaml"

	# Check pod creation
	kubectl wait --for=condition=Ready pod "$pod_name"

	# Check liveness probe returns a success code
	kubectl describe pod "$pod_name" | grep -E "Liveness|#success=1"

	# Sleep necessary to check liveness probe returns a failure code
	sleep "$sleep_liveness"
	kubectl describe pod "$pod_name" | grep "Started container"
}

teardown() {
	[ "${CI_JOB}" == "CRIO_K8S" ] && skip "test not working - see: ${issue}"
	kubectl delete pod "$pod_name"
}
