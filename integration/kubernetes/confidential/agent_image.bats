#!/usr/bin/env bats
# Copyright (c) 2022 IBM Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

load "${BATS_TEST_DIRNAME}/lib.sh"
load "${BATS_TEST_DIRNAME}/../../confidential/lib.sh"

# Images used on the tests.
## Cosign
image_cosigned="quay.io/kata-containers/confidential-containers:cosign-signed"
image_cosigned_other="quay.io/kata-containers/confidential-containers:cosign-signed-key2"

## Simple Signing
tag_suffix=""
if [ "$(uname -m)" != "x86_64" ]; then
	tag_suffix="-$(uname -m)"
fi
image_simple_signed="quay.io/kata-containers/confidential-containers:signed${tag_suffix}"
image_signed_protected_other="quay.io/kata-containers/confidential-containers:other_signed${tag_suffix}"
image_unsigned_protected="quay.io/kata-containers/confidential-containers:unsigned${tag_suffix}"
image_unsigned_unprotected="quay.io/prometheus/busybox:latest"

## Authenticated Image
image_authenticated="quay.io/kata-containers/confidential-containers-auth:test"

original_kernel_params=$(get_kernel_params)
# Allow to configure the runtimeClassName on pod configuration.
RUNTIMECLASS="${RUNTIMECLASS:-kata}"
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

setup() {
	start_date=$(date +"%Y-%m-%d %H:%M:%S")

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

@test "$test_tag Test can launch pod with measured boot enabled" {
	switch_measured_rootfs_verity_scheme dm-verity
	pod_config="$(new_pod_config "$image_unsigned_unprotected")"
	echo $pod_config

	create_test_pod
}

@test "$test_tag Test cannnot launch pod with measured boot enabled and rootfs modified" {
	switch_measured_rootfs_verity_scheme dm-verity
	setup_signature_files
	pod_config="$(new_pod_config "$image_unsigned_unprotected")"
	echo $pod_config

	assert_pod_fail "$pod_config"
}

@test "$test_tag Test can pull an unencrypted image inside the guest" {
	create_test_pod

	echo "Check the image was not pulled in the host"
	local pod_id=$(kubectl get pods -o jsonpath='{.items..metadata.name}')
	retrieve_sandbox_id
	rootfs=($(find /run/kata-containers/shared/sandboxes/${sandbox_id}/shared \
		-name rootfs))
	[ ${#rootfs[@]} -eq 1 ]
}

@test "$test_tag Test can pull a unencrypted signed image from a protected registry" {
	setup_signature_files
	create_test_pod
}

@test "$test_tag Test cannot pull an unencrypted unsigned image from a protected registry" {
	setup_signature_files
	local container_config="$(new_pod_config "$image_unsigned_protected")"

	echo $container_config
	assert_pod_fail "$container_config"
	assert_logs_contain 'Validate image failed: The signatures do not satisfied! Reject reason: \[Match reference failed.\]'
}

@test "$test_tag Test can pull an unencrypted unsigned image from an unprotected registry" {
	setup_signature_files
	pod_config="$(new_pod_config "$image_unsigned_unprotected")"
	echo $pod_config

	create_test_pod
}

@test "$test_tag Test unencrypted signed image with unknown signature is rejected" {
	setup_signature_files
	local container_config="$(new_pod_config "$image_signed_protected_other")"
	echo $container_config

	assert_pod_fail "$container_config"
	assert_logs_contain 'Validate image failed: The signatures do not satisfied! Reject reason: \[signature verify failed! There is no pubkey can verify the signature!\]'
}

@test "$test_tag Test unencrypted image signed with cosign" {
	setup_cosign_signatures_files
	pod_config="$(new_pod_config "$image_cosigned")"
	echo $pod_config

	create_test_pod
}

@test "$test_tag Test unencrypted image with unknown cosign signature" {
	setup_cosign_signatures_files
	local container_config="$(new_pod_config "$image_cosigned_other")"
	echo $container_config

	assert_pod_fail "$container_config"
	assert_logs_contain 'Validate image failed: \[PublicKeyVerifier { key: CosignVerificationKey'
}


@test "$test_tag Test pull an unencrypted unsigned image from an authenticated registry with correct credentials" {
	if [ "${AA_KBC}" = "offline_fs_kbc" ]; then
		setup_credentials_files "quay.io/kata-containers/confidential-containers-auth"
	elif [ "${AA_KBC}" = "eaa_kbc" ]; then
		# EAA KBC is specified as: eaa_kbc::host_ip:port, and 50000 is the default port used
		# by the service, as well as the one configured in the Kata Containers rootfs.
		add_kernel_params "agent.aa_kbc_params=eaa_kbc::$(hostname -I | awk '{print $1}'):50000"
	fi

	pod_config="$(new_pod_config "${image_authenticated}")"
	echo $pod_config

	create_test_pod
}

@test "$test_tag Test cannot pull an image from an authenticated registry with incorrect credentials" {
	if [ "${AA_KBC}" = "eaa_kbc" ]; then
		skip "As the test requires changing verdictd configuration and restarting its service"
	fi

	REGISTRY_CREDENTIAL_ENCODED="QXJhbmRvbXF1YXl0ZXN0YWNjb3VudHRoYXRkb2VzbnRleGlzdDpwYXNzd29yZAo=" setup_credentials_files "quay.io/kata-containers/confidential-containers-auth"

	pod_config="$(new_pod_config "${image_authenticated}")"
	echo "Pod config: ${pod_config}"

	assert_pod_fail "${pod_config}"
	assert_logs_contain 'failed to pull manifest Authentication failure'
}

@test "$test_tag Test cannot pull an image from an authenticated registry without credentials" {
	pod_config="$(new_pod_config "${image_authenticated}")"
	echo "Pod config: ${pod_config}"

	assert_pod_fail "${pod_config}"
	assert_logs_contain 'failed to pull manifest Not authorized'
}

teardown() {
	# Print the logs and cleanup resources.
	echo "-- Kata logs:"
	sudo journalctl -xe -t kata --since "$start_date" -n 100000

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
