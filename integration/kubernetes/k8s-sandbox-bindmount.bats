#!/usr/bin/env bats
#
# Copyright (c) 2022 Apple Inc.
#
# SPDX-License-Identifier: Apache-2.0
#

load "${BATS_TEST_DIRNAME}/../../.ci/lib.sh"
load "${BATS_TEST_DIRNAME}/tests_common.sh"

setup() {
	
	SYSCONFIG_FILE="/etc/kata-containers/configuration.toml"
	QEMU_CFG="/usr/share/defaults/kata-containers/configuration-qemu.toml"
	CLH_CFG="/usr/share/defaults/kata-containers/configuration-clh.toml"
	DEFAULT_CFG="/usr/share/defaults/kata-containers/configuration.toml"
	TEST_FILE="test-file"
	TEST_FILE_HOST_PATH="/usr/share/kata-containers/$TEST_FILE"
	pod_name="qos-test"
	
	sudo mkdir -p "$(dirname ${SYSCONFIG_FILE})"

	if [ "${KATA_HYPERVISOR}" == "qemu" ];  then
		cfg="${QEMU_CFG}"
	elif [ "${HYPERVISOR}" == "cloud-hypervisor" ]; then
		cfg="${CLH_CFG}"
	else
		cfg="${DEFAULT_CFG}"
	fi

	[ -z "${cfg}" ] && echo "Configuration file not found" >&2 && false

	cp -a "${cfg}" "${SYSCONFIG_FILE}"

        sudo sed -i 's|sandbox_bind_mounts.*|sandbox_bind_mounts=["'$TEST_FILE_HOST_PATH'"]|g' "${SYSCONFIG_FILE}"
	echo "hello" > "${TEST_FILE_HOST_PATH}"

	get_pod_config_dir
}

@test "Check sandbox bindmount support" {
	[ "${KATA_HYPERVISOR}" == "firecracker" ] && skip "test not working see: ${fc_limitations}"

        # Create pod
        kubectl apply -f "${pod_config_dir}/pod-guaranteed.yaml"
        # Check pod creation
        kubectl wait --for=condition=Ready --timeout="$timeout" pod "$pod_name"

	# Verify existence and permission of sandbox bindmount in the guest:
	pod_id=$(sudo -E crictl pods -q -s Ready --name "$pod_name")

	sudo ./ro-volume-exp.sh "$pod_id" sandbox-mounts "$TEST_FILE" | grep "Read-only file system"
}

teardown() {
	kubectl delete pod "$pod_name"
	cat "$SYSCONFIG_FILE"
	rm "$TEST_FILE_HOST_PATH"
	rm "$SYSCONFIG_FILE"
}
