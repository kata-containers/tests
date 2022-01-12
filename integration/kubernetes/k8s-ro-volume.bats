#!/usr/bin/env bats
#
# Copyright (c) 2021 Ant Group
#
# SPDX-License-Identifier: Apache-2.0
#

load "${BATS_TEST_DIRNAME}/../../.ci/lib.sh"
load "${BATS_TEST_DIRNAME}/tests_common.sh"
fc_limitations="https://github.com/kata-containers/documentation/issues/351"

setup() {
	[ "${KATA_HYPERVISOR}" == "firecracker" ] && skip "test not working see: ${fc_limitations}"
	pod_name="test-readonly-volume"
	container_name="busybox-ro-volume-container"
	tmp_file="ro-volume-test-foobarfoofoo"
	ro_volume_suffix="-tmp"
	get_pod_config_dir
}

@test "Test readonly volume for pods" {
	[ "${KATA_HYPERVISOR}" == "firecracker" ] && skip "test not working see: ${fc_limitations}"
	# Create pod
	kubectl create -f "${pod_config_dir}/pod-readonly-volume.yaml"

	# Check pod creation
	kubectl wait --for=condition=Ready --timeout=$timeout pod "$pod_name"

	# Validate readonly volume mount inside pod
	check_cmd="mount|grep /tmp"
	kubectl exec $pod_name -- sh -c "$check_cmd" | grep '\<ro\>'

	# Validate readonly volume mount in the guest
	pod_id=$(sudo -E crictl pods -q -s Ready --name $pod_name)
	sudo ./ro-volume-exp.sh $pod_id $ro_volume_suffix $tmp_file || true
	sudo ls -lR $shared_mounts/ | grep $tmp_file && echo "should not find $tmp_file in shared mounts" && false
	sudo ls -lR $host_mounts/ | grep $tmp_file && echo "should not find $tmp_file in host mounts" && false

	# Validate readonly volume mount on the host
	container_id=$(sudo -E crictl ps -q --state Running --name $container_name)
	shared_mounts="/run/kata-containers/shared/sandboxes/$pod_id/shared/"
	host_mounts="/run/kata-containers/shared/sandboxes/$pod_id/mounts/"
	mount | grep $shared_mounts | grep $container_id | grep -- $ro_volume_suffix | grep '\<ro\>'
	mount | grep $host_mounts | grep $container_id | grep -- $ro_volume_suffix | grep '\<ro\>'

}

teardown() {
	[ "${KATA_HYPERVISOR}" == "firecracker" ] && skip "test not working see: ${fc_limitations}"
	kubectl delete pod "$pod_name"
}
