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

	# Create test .yaml
	sed -e "s/\${nginx_version}/${nginx_image}/" \
		"${pod_config_dir}/${deployment}.yaml" > "${pod_config_dir}/test-${deployment}.yaml"

	kubectl create -f "${pod_config_dir}/test-${deployment}.yaml"
	kubectl wait --for=condition=Available --timeout=$timeout deployment/${deployment}
	kubectl expose deployment/${deployment}

	busybox_pod="test-nginx"
	cmd='kubectl delete pod "$busybox_pod" || (kubectl run $busybox_pod --restart=Never --image="$busybox_image" -- wget --timeout=5 "$deployment"
		&& kubectl get pods | grep $busybox_pod | grep Completed
		&& kubectl logs "$busybox_pod" | grep "index.html"
		&& kubectl delete pod "$busybox_pod")'
	waitForProcess "$wait_time" "$sleep_time" "$cmd"
}

teardown() {
	# Debugging information
	kubectl describe "pod/$busybox_pod"
	kubectl get "pod/$busybox_pod" -o yaml
	kubectl get deployment/${deployment} -o yaml
	kubectl get service/${deployment} -o yaml
	cat /var/log/pods/default_test-nginx_*/test-nginx/0.log || true

	rm -f "${pod_config_dir}/test-${deployment}.yaml"
	kubectl delete deployment "$deployment"
	kubectl delete service "$deployment"
	kubectl delete pod "$busybox_pod"
}
