#
# Copyright (c) 2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

load "${BATS_TEST_DIRNAME}/../../.ci/lib.sh"
load "${BATS_TEST_DIRNAME}/tests_common.sh"

setup() {
	export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
	get_pod_config_dir
}

@test "Pod quota" {
	resource_name="pod-quota"
	deployment_name="deploymenttest"
	namespace="test-quota-ns"

	# Create the resourcequota
	kubectl create -f "${pod_config_dir}/resource-quota.yaml"

	# View information about resourcequota
	kubectl get -n "$namespace" resourcequota "$resource_name" \
		--output=yaml | grep 'pods: "2"'

	# Create deployment
	kubectl create -f "${pod_config_dir}/pod-quota-deployment.yaml"

	# View deployment
	kubectl wait --for=condition=Available --timeout=$timeout \
		-n "$namespace" deployment/${deployment_name}

	# Check the quota was filled out
	used_pods=$(kubectl get -n "$namespace" resourcequota \
		--output=jsonpath={.items[0].status.used.pods})
	[ "$used_pods" -eq 2 ]
}

teardown() {
	kubectl delete -n "$namespace" deployment "$deployment_name"
	kubectl delete -f "${pod_config_dir}/resource-quota.yaml"
}
