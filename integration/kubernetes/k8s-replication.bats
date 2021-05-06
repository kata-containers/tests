#!/usr/bin/env bats
#
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

load "${BATS_TEST_DIRNAME}/../../.ci/lib.sh"
load "${BATS_TEST_DIRNAME}/tests_common.sh"

setup() {
	nginx_version=$(get_test_version "docker_images.nginx.version")
	nginx_image="nginx:$nginx_version"

	export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
	get_pod_config_dir
}

@test "Replication controller" {
	replication_name="replicationtest"
	number_of_replicas="1"

	# Create yaml
	sed -e "s/\${nginx_version}/${nginx_image}/" \
		"${pod_config_dir}/replication-controller.yaml" > "${pod_config_dir}/test-replication-controller.yaml"

	# Create replication controller
	kubectl create -f "${pod_config_dir}/test-replication-controller.yaml"

	# Check replication controller
	kubectl describe replicationcontrollers/"$replication_name" | grep "replication-controller"

	# Check pod creation
	pod_name=$(kubectl get pods --output=jsonpath={.items..metadata.name})
	cmd="kubectl wait --timeout=$timeout --for=condition=Ready pod $pod_name"
	waitForProcess "$wait_time" "$sleep_time" "$cmd"

	# Check number of pods created for the
	# replication controller is equal to the
	# number of replicas that we defined
	launched_pods=$(echo $pod_name | wc -l)

	[ "$launched_pods" -eq "$number_of_replicas" ]
}

teardown() {
	rm -f "${pod_config_dir}/test-replication-controller.yaml"
	kubectl delete pod "$pod_name"
	kubectl delete rc "$replication_name"
}
