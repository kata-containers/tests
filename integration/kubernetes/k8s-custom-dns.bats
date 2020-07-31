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
    BASH_XTRACEFD=3
    set -x
	# Create the pod
	kubectl create -f "${pod_config_dir}/pod-custom-dns.yaml"

	# Check pod creation
	kubectl wait --for=condition=Ready pod "$pod_name"
	kubectl get pod "$pod_name" -o yaml

	# Check dns config at /etc/resolv.conf
	kubectl -v=8 exec -it "$pod_name" -- cat "$file_name" &
	kubectl -v=8 exec -it "$pod_name" -- cat "$file_name" &
	kubectl -v=8 exec -it "$pod_name" -- cat "$file_name" &
	kubectl -v=8 exec -it "$pod_name" -- cat "$file_name" &
	kubectl -v=8 exec -it "$pod_name" -- cat "$file_name" &
	kubectl -v=8 exec -it "$pod_name" -- cat "$file_name" &
	kubectl -v=8 exec -it "$pod_name" -- cat "$file_name" &
	kubectl -v=8 exec -it "$pod_name" -- cat "$file_name" &
	kubectl -v=8 exec -it "$pod_name" -- cat "$file_name" &
	kubectl -v=8 exec -it "$pod_name" -- cat "$file_name" &
	kubectl -v=8 exec -it "$pod_name" -- cat "$file_name" &
	sleep 60
	j=$(ps -ef | grep kubectl | grep -v kubectl)
	return 1
}

teardown() {
	kubectl get pod "$pod_name" -o yaml
	kubectl delete pod "$pod_name"
}
