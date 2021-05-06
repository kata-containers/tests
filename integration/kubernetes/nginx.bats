#!/usr/bin/env bats
#
# Copyright (c) 2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

load "${BATS_TEST_DIRNAME}/../../.ci/lib.sh"
load "${BATS_TEST_DIRNAME}/tests_common.sh"

setup() {
	nginx_version=$(get_test_version "docker_images.nginx.version")
	nginx_image="nginx:$nginx_version"
	busybox_image="busybox"
	deployment="nginx-deployment"
	export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
	# Pull the images before launching workload.
	crictl_pull "$busybox_image"
	crictl_pull "$nginx_image"

	get_pod_config_dir
}

@test "Verify nginx connectivity between pods" {
	wait_time=90
	sleep_time=3

	# Create test .yaml
	sed -e "s/\${nginx_version}/${nginx_image}/" \
		"${pod_config_dir}/${deployment}.yaml" > "${pod_config_dir}/test-${deployment}.yaml"

	kubectl create -f "${pod_config_dir}/test-${deployment}.yaml"
	kubectl wait --for=condition=Available --timeout=$timeout deployment/${deployment}
	kubectl expose deployment/${deployment}

	busybox_pod="test-nginx"
	kubectl run $busybox_pod --restart=Never --image="$busybox_image" \
		-- wget --timeout=5 "$deployment"
	cmd="kubectl get pods | grep $busybox_pod | grep Completed"
	waitForProcess "$wait_time" "$sleep_time" "$cmd"
	kubectl logs "$busybox_pod" | grep "index.html"
	kubectl describe pod "$busybox_pod"
}

teardown() {
	# Debugging information
	kubectl describe "pod/$busybox_pod"

	rm -f "${pod_config_dir}/test-${deployment}.yaml"
	kubectl delete deployment "$deployment"
	kubectl delete service "$deployment"
	kubectl delete pod "$busybox_pod"
}
