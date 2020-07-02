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
	pod_name="custom-dns-test"
	file_name="/etc/resolv.conf"
	get_pod_config_dir
}

@test "Check custom dns" {
	wait_time=20
	sleep_time=2

	# Create the pod
	kubectl create -f "${pod_config_dir}/pod-custom-dns.yaml"

	# Check pod creation
	cmd="kubectl wait --for=condition=Ready pod $pod_name"
	waitForProcess "$wait_time" "$sleep_time" "$cmd"

	# Check dns config at /etc/resolv.conf
	kubectl exec -it "$pod_name" -- cat "$file_name" | grep -q "nameserver 1.2.3.4"
	kubectl exec -it "$pod_name" -- cat "$file_name" | grep -q "search dns.test.search"
}

teardown() {
	kubectl delete pod "$pod_name"
	run check_pods
	echo "$output"
	[ "$status" -eq 0 ]
}
