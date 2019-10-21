#!/usr/bin/env bats
#
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#
#

load "${BATS_TEST_DIRNAME}/../../.ci/lib.sh"
load "${BATS_TEST_DIRNAME}/../../lib/common.bash"

setup() {
	versions_file="${BATS_TEST_DIRNAME}/../../versions.yaml"
	nginx_version=$("${GOPATH}/bin/yq" read "$versions_file" "docker_images.nginx.version")
	nginx_image="nginx:$nginx_version"
	export KUBECONFIG="$HOME/.kube/config"
	deployment="nginx-deployment"
	image="busybox"
	get_pod_config_dir
}

@test "Patch deployment" {
	wait_time=20
	sleep_time=2

	sed -e "s/\${nginx_version}/${nginx_image}/" \
		"${pod_config_dir}/${deployment}.yaml" > "${pod_config_dir}/test-${deployment}.yaml"

	# Create deployment
	kubectl create -f "${pod_config_dir}/test-${deployment}.yaml"

	# Check deployment creation
	cmd="kubectl wait --for=condition=Available deployment/${deployment}"
	waitForProcess "$wait_time" "$sleep_time" "$cmd"

	# Expose deployment
	kubectl expose deployment/${deployment}

	# Patch deployment
	kubectl patch deployment ${deployment} --patch "$(cat ${pod_config_dir}/patch-file.yaml)"

	# Verify patch
	cmd="kubectl get pods -o jsonpath="{.items[*].spec.containers[*].image}" | grep ${image}"
	waitForProcess "$wait_time" "$sleep_time" "$cmd"

	# Get pod names
	pod_name=$(kubectl get pods -o jsonpath='{.items[*].metadata.name}')
}

teardown() {
	kubectl delete pod ${pod_name}
	kubectl delete deployment ${deployment}
	kubectl delete service ${deployment}
}
