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
	# Create the pod
	echo "============Check custom dns 0==========="
	kubectl create -f "${pod_config_dir}/pod-custom-dns.yaml"

	echo "============Check custom dns 1==========="
	# Check pod creation
	kubectl wait --for=condition=Ready pod "$pod_name"
	echo "============Check custom dns 2==========="

	# Check dns config at /etc/resolv.conf
	kubectl exec -it "$pod_name" -- cat "$file_name" | grep -q "nameserver 1.2.3.4"
	echo "============Check custom dns 3==========="
	kubectl exec -it "$pod_name" -- cat "$file_name" | grep -q "search dns.test.search"
	echo "============Check custom dns 4==========="
}

teardown() {
	kubectl delete pod "$pod_name"
}
