#!/usr/bin/env bats
# Copyright (c) 2022 IBM Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

load "${BATS_TEST_DIRNAME}/lib.sh"
load "${BATS_TEST_DIRNAME}/../../confidential/lib.sh"

test_tag="[cc][agent][kubernetes][containerd]"

# Create the test pod.
#
# Note: the global $sandbox_name, $pod_config should be set
# 	already. It also relies on $CI and $DEBUG exported by CI scripts or
# 	the developer, to decide how to set debug flags.
#
create_test_pod() {
	# On CI mode we only want to enable the agent debug for the case of
	# the test failure to obtain logs.
	if [ "${CI:-}" == "true" ]; then
		enable_full_debug
	elif [ "${DEBUG:-}" == "true" ]; then
		enable_full_debug
		enable_agent_console
	fi

	echo "Create the test sandbox"
	echo "Pod config is: "$pod_config
	kubernetes_create_cc_pod $pod_config
}

setup() {
	start_date=$(date +"%Y-%m-%d %H:%M:%S")

	sandbox_name="busybox-cc"
	pod_config="${FIXTURES_DIR}/pod-config.yaml"
	pod_id=""

	echo "Delete any existing ${sandbox_name} pod"
	kubernetes_delete_cc_pod_if_exists "$sandbox_name"

	echo "Prepare containerd for Confidential Container"
	SAVED_CONTAINERD_CONF_FILE="/etc/containerd/config.toml.$$"
	configure_cc_containerd "$SAVED_CONTAINERD_CONF_FILE"

	echo "Reconfigure Kata Containers"
	switch_image_service_offload on
	clear_kernel_params
	add_kernel_params \
		"agent.container_policy_file=/etc/containers/quay_verification/quay_policy.json"
	
	copy_files_to_guest
}

# Check the logged messages on host have a given message.
# Parameters:
#      $1 - the message
#
# Note: get the logs since the global $start_date.
#
assert_logs_contain() {
	local message="$1"
	journalctl -x -t kata --since "$start_date" | grep "$message"
}

@test "$test_tag Test can pull an unencrypted image inside the guest" {
	local container_config="${FIXTURES_DIR}/pod-config.yaml"

	create_test_pod

	echo "Check the image was not pulled in the host"
	local pod_id=$(kubectl get pods -o jsonpath='{.items..metadata.name}')
	retrieve_sandbox_id
	rootfs=($(find /run/kata-containers/shared/sandboxes/${sandbox_id}/shared \
		-name rootfs))
	[ ${#rootfs[@]} -eq 1 ]
}

@test "$test_tag Test can pull a unencrypted signed image from a protected registry" {
	skip_if_skopeo_not_present
	local container_config="${FIXTURES_DIR}/pod-config.yaml"

	create_test_pod
}

@test "$test_tag Test cannot pull an unencrypted unsigned image from a protected registry" {
	skip_if_skopeo_not_present
	local container_config="${FIXTURES_DIR}/pod-config_unsigned-protected.yaml"

	echo $container_config
	assert_pod_fail "$container_config"

	assert_logs_contain 'Signature for identity .* is not accepted'
}

@test "$test_tag Test can pull an unencrypted unsigned image from an unprotected registry" {
	skip_if_skopeo_not_present
	pod_config="${FIXTURES_DIR}/pod-config_unsigned-unprotected.yaml"
	echo $pod_config

	create_test_pod
}

@test "$test_tag Test unencrypted signed image with unknown signature is rejected" {
	skip_if_skopeo_not_present
	local container_config="${FIXTURES_DIR}/pod-config_signed-protected-other.yaml"

	assert_pod_fail "$container_config"
	assert_logs_contain "Invalid GPG signature"
}

teardown() {
	# Print the logs and cleanup resources.
	echo "-- Kata logs:"
	sudo journalctl -xe -t kata --since "$start_date"

	# Allow to not destroy the environment if you are developing/debugging
	# tests.
	if [[ "${CI:-false}" == "false" && "${DEBUG:-}" == true ]]; then
		echo "Leaving changes and created resources untoughted"
		return
	fi

	kubernetes_delete_cc_pod_if_exists "$sandbox_name" || true

	clear_kernel_params
	switch_image_service_offload off
	disable_full_debug
}
