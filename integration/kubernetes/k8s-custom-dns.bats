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
	kubectl create -f "${pod_config_dir}/pod-custom-dns.yaml"

	# Check pod creation
	kubectl wait --for=condition=Ready pod "$pod_name"

	# Check dns config at /etc/resolv.conf
	echo "111111111111111" 1>&2
	kubectl -v=8 exec -t "$pod_name" -- cat "$file_name" | grep -q "nameserver 1.2.3.4"

	echo "22222222222222" 1>&2
	kubectl  -v=8 exec -i "$pod_name" -- sh <<EOC
cat ${file_name} | grep -q "search dns.test.search"
EOC

	echo "3333333333333" 1>&2
	echo $? 1>&2

	kubectl -v=8 exec -t "$pod_name" -- cat "$file_name" | grep -q "nameserver 1.2.3.4"
	kubectl -v=8 exec -t "$pod_name" -- cat "$file_name" | grep -q "nameserver 1.2.3.4"
	kubectl -v=8 exec -t "$pod_name" -- cat "$file_name" | grep -q "nameserver 1.2.3.4"
	kubectl -v=8 exec -t "$pod_name" -- cat "$file_name" | grep -q "nameserver 1.2.3.4"
	kubectl -v=8 exec -t "$pod_name" -- cat "$file_name" | grep -q "nameserver 1.2.3.4"
	kubectl -v=8 exec -t "$pod_name" -- cat "$file_name" | grep -q "nameserver 1.2.3.4"
	kubectl -v=8 exec -i "$pod_name" -- cat "$file_name" | grep -q "nameserver 1.2.3.4"
	kubectl -v=8 exec -i "$pod_name" -- cat "$file_name" | grep -q "nameserver 1.2.3.4"
	kubectl -v=8 exec -i "$pod_name" -- cat "$file_name" | grep -q "nameserver 1.2.3.4"
}

teardown() {
	kubectl delete pod "$pod_name"
}
