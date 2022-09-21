#!/usr/bin/env bats
# Copyright (c) 2022 IBM Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

load "${BATS_TEST_DIRNAME}/lib.sh"
load "${BATS_TEST_DIRNAME}/../../confidential/lib.sh"

test_tag="[cc][agent][kubernetes][containerd]"
original_kernel_params=$(get_kernel_params)

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
	add_kernel_params "${original_kernel_params}"
	if [ "${SKOPEO:-}" = "yes" ]; then
		add_kernel_params \
			"agent.container_policy_file=/etc/containers/quay_verification/quay_policy.json"
	fi

	# In case the tests run behind a firewall where images needed to be fetched
	# through a proxy.
	local https_proxy="${HTTPS_PROXY:-${https_proxy:-}}"
	if [ -n "$https_proxy" ]; then
		echo "Enable agent https proxy"
		add_kernel_params "agent.https_proxy=$https_proxy"

		local local_dns=$(grep nameserver /etc/resolv.conf \
			/run/systemd/resolve/resolv.conf  2>/dev/null \
			|grep -v "127.0.0.53" | cut -d " " -f 2 | head -n 1)
		local new_file="${BATS_FILE_TMPDIR}/$(basename ${pod_config})"
		echo "New pod configuration with local dns: $new_file"
		cp -f "${pod_config}" "${new_file}"
		pod_config="$new_file"
		sed -i -e 's/8.8.8.8/'${local_dns}'/' "${pod_config}"
		cat "$pod_config"
	fi
	
	if [ "${SKOPEO:-}" = "yes" ]; then
		setup_skopeo_signature_files_in_guest
	else
		setup_offline_fs_kbc_signature_files_in_guest
	fi
}

# Check the logged messages on host have a given message.
# Parameters:
#      $1 - the message
#
# Note: get the logs since the global $start_date.
#
assert_logs_contain() {
	local message="$1"
	# Note: with image-rs we get more that the default 1000 lines of logs
	journalctl -x -t kata --since "$start_date" -n 100000 | grep "$message"
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
	local container_config="${FIXTURES_DIR}/pod-config.yaml"

	create_test_pod
}

@test "$test_tag Test cannot pull an unencrypted unsigned image from a protected registry" {
	local container_config="${FIXTURES_DIR}/pod-config_unsigned-protected.yaml"

	echo $container_config
	assert_pod_fail "$container_config"
	if [ "${SKOPEO:-}" = "yes" ]; then
		assert_logs_contain 'Signature for identity .* is not accepted'
	else
		assert_logs_contain 'Validate image failed: The signatures do not satisfied! Reject reason: \[Match reference failed.\]'
	fi
}

@test "$test_tag Test can pull an unencrypted unsigned image from an unprotected registry" {
	pod_config="${FIXTURES_DIR}/pod-config_unsigned-unprotected.yaml"
	echo $pod_config

	create_test_pod
}

@test "$test_tag Test unencrypted signed image with unknown signature is rejected" {
	local container_config="${FIXTURES_DIR}/pod-config_signed-protected-other.yaml"

	assert_pod_fail "$container_config"
	if [ "${SKOPEO:-}" = "yes" ]; then
		assert_logs_contain "Invalid GPG signature"
	else
		assert_logs_contain 'Validate image failed: The signatures do not satisfied! Reject reason: \[signature verify failed! There is no pubkey can verify the signature!\]'
	fi
}

teardown() {
	# Print the logs and cleanup resources.
	echo "-- Kata logs:"
	sudo journalctl -xe -t kata --since "$start_date" -n 100000

	# Allow to not destroy the environment if you are developing/debugging
	# tests.
	if [[ "${CI:-false}" == "false" && "${DEBUG:-}" == true ]]; then
		echo "Leaving changes and created resources untoughted"
		return
	fi

	kubernetes_delete_cc_pod_if_exists "$sandbox_name" || true

	clear_kernel_params
	add_kernel_params "${original_kernel_params}"
	switch_image_service_offload off
	disable_full_debug
}
