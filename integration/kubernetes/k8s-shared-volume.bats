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
	[ "${CI_JOB}" == "CRIO_K8S" ] && skip "test not working - see: ${issue}"
	export KUBECONFIG="$HOME/.kube/config"
	get_pod_config_dir
}

@test "Containers with shared volume" {
	[ "${CI_JOB}" == "CRIO_K8S" ] && skip "test not working - see: ${issue}"
	pod_name="test-shared-volume"
	first_container_name="busybox-first-container"
	second_container_name="busybox-second-container"

	# Create pod
	kubectl create -f "${pod_config_dir}/pod-shared-volume.yaml"

	# Check pods
	kubectl wait --for=condition=Ready pod "$pod_name"

	# Communicate containers
	cmd="cat /tmp/pod-data"
	msg="Hello from the $second_container_name"
	kubectl exec "$pod_name" -c "$first_container_name" -- sh -c "$cmd" | grep "$msg"
}

@test "initContainer with shared volume" {
	[ "${CI_JOB}" == "CRIO_K8S" ] && skip "test not working - see: ${issue}"
	pod_name="initcontainer-shared-volume"
	last_container="last"

	# Create pod
	kubectl create -f "${pod_config_dir}/initContainer-shared-volume.yaml"

	# Check pods
	kubectl wait --for=condition=Ready pod "$pod_name"

	cmd='test $(cat /volume/initContainer) -lt $(cat /volume/container)'
	kubectl exec "$pod_name" -c "$last_container" -- sh -c "$cmd"
}

teardown() {
	[ "${CI_JOB}" == "CRIO_K8S" ] && skip "test not working - see: ${issue}"
	kubectl delete pod "$pod_name"
}
