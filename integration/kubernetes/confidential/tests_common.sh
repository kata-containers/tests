#!/bin/bash
# Copyright (c) 2021, 2023 IBM Corporation
#
# SPDX-License-Identifier: Apache-2.0
#
# This provides generic functions to use in the tests.
#

load "${BATS_TEST_DIRNAME}/lib.sh"
load "${BATS_TEST_DIRNAME}/../../confidential/lib.sh"

original_kernel_params=$(get_kernel_params)

# Common setup for tests.
#
# Global variables exported:
#	$test_start_date     - test start time.
#	$pod_config          - path to default pod configuration file.
#	$original_kernel_params - saved the original list of kernel parameters.
#
setup_common() {
	test_start_date=$(date +"%Y-%m-%d %H:%M:%S")

	pod_config="$(new_pod_config "$image_simple_signed")"
	pod_id=""

	kubernetes_delete_all_cc_pods_if_any_exists || true

	echo "Prepare containerd for Confidential Container"
	SAVED_CONTAINERD_CONF_FILE="/etc/containerd/config.toml.$$"
	configure_cc_containerd "$SAVED_CONTAINERD_CONF_FILE"

	echo "Reconfigure Kata Containers"
	switch_image_service_offload on
	clear_kernel_params
	add_kernel_params "${original_kernel_params}"
	
	setup_proxy
	switch_measured_rootfs_verity_scheme none
}

# Common teardown for tests. Use alongside setup_common().
#
teardown_common() {
	# Print the logs and cleanup resources.
	echo "-- Kata logs:"
	sudo journalctl -xe -t kata --since "$test_start_date" -n 100000

	# Allow to not destroy the environment if you are developing/debugging
	# tests.
	if [[ "${CI:-false}" == "false" && "${DEBUG:-}" == true ]]; then
		echo "Leaving changes and created resources untouched"
		return
	fi

	kubernetes_delete_all_cc_pods_if_any_exists || true
	clear_kernel_params
	add_kernel_params "${original_kernel_params}"
	switch_image_service_offload off
	disable_full_debug
}


# Create the test pod.
#
# Note: the global $pod_config should be set in setup_common
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
	echo "Pod config is: $pod_config"
	kubernetes_create_cc_pod $pod_config
}

# Create a pod configuration out of a template file.
#
# Parameters:
#	$1 - the container image.
# Return:
# 	the path to the configuration file. The caller should not care about
# 	its removal afterwards as it is created under the bats temporary
# 	directory.
#
# Environment variables:
#	RUNTIMECLASS: set the runtimeClassName value from $RUNTIMECLASS.
#
new_pod_config() {
	local base_config="${FIXTURES_DIR}/pod-config.yaml.in"
	local image="$1"

	local new_config=$(mktemp "${BATS_FILE_TMPDIR}/$(basename ${base_config}).XXX")
	IMAGE="$image" RUNTIMECLASS="$RUNTIMECLASS" envsubst < "$base_config" > "$new_config"
	echo "$new_config"
}
