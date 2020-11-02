#!/usr/bin/env bats
#
# Copyright (c) 2021 Ant Group
#
# SPDX-License-Identifier: Apache-2.0
#

load "${BATS_TEST_DIRNAME}/../../.ci/lib.sh"
load "${BATS_TEST_DIRNAME}/tests_common.sh"

setup() {
	export KUBECONFIG="$HOME/.kube/config"
	pod_name="test-readonly-volume"
	container_name="busybox-ro-volume-container"
	ro_volume_suffix="-tmp"
	get_pod_config_dir
}

@test "Test readonly volume for pods" {
	# Create pod
	kubectl create -f "${pod_config_dir}/pod-readonly-volume.yaml"

	# Check pod creation
	kubectl wait --for=condition=Ready --timeout=$timeout pod "$pod_name"

	# Validate readonly volume mount inside pod
	check_cmd="mount|grep /tmp"
	kubectl exec $pod_name -- sh -c "$check_cmd" | grep '\<ro\>'

	# Validate readonly volume mount in the guest
	pod_id=$(sudo -E crictl pods -q -s Ready --name $pod_name)
	sudo ./ro-volume-exp.sh $pod_id $ro_volume_suffix | grep "Read-only file system"

	# Validate readonly volume mount on the host
	container_id=$(sudo -E crictl ps -q --state Running --name $container_name)
	shared_mounts="/run/kata-containers/shared/sandboxes/$pod_id/shared/"
	host_mounts="/run/kata-containers/shared/sandboxes/$pod_id/mounts/"
	mount | grep $shared_mounts | grep $container_id | grep -- $ro_volume_suffix | grep '\<ro\>'
	mount | grep $host_mounts | grep $container_id | grep -- $ro_volume_suffix | grep '\<ro\>'
}

teardown() {
	kubectl delete pod "$pod_name"
}
