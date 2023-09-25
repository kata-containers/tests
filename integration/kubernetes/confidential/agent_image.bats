#!/usr/bin/env bats
# Copyright (c) 2022 IBM Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

load "${BATS_TEST_DIRNAME}/tests_common.sh"

tag_suffix=""
if [ "$(uname -m)" != "x86_64" ]; then
	tag_suffix="-$(uname -m)"
fi

# Images used on the tests.
## Cosign 
image_cosigned="quay.io/kata-containers/confidential-containers:cosign-signed${tag_suffix}"
image_cosigned_other="quay.io/kata-containers/confidential-containers:cosign-signed-key2"

## Simple Signing

image_simple_signed="quay.io/kata-containers/confidential-containers:signed${tag_suffix}"
image_signed_protected_other="quay.io/kata-containers/confidential-containers:other_signed${tag_suffix}"
image_unsigned_protected="quay.io/kata-containers/confidential-containers:unsigned${tag_suffix}"
image_unsigned_unprotected="quay.io/prometheus/busybox:latest"

## Authenticated Image
image_authenticated="quay.io/kata-containers/confidential-containers-auth:test"

# Allow to configure the runtimeClassName on pod configuration.
RUNTIMECLASS="${RUNTIMECLASS:-kata}"
test_tag="[cc][agent][kubernetes][containerd]"

setup() {
	setup_common
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

@test "$test_tag Test cannot pull an unencrypted unsigned image from a protected registry" {
	setup_signature_files
	local container_config="$(new_pod_config "$image_unsigned_protected")"

	echo $container_config
	assert_pod_fail "$container_config"
	assert_logs_contain 'Validate image failed: The signatures do not satisfied! Reject reason: \[Match reference failed.\]'
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
	assert_logs_contain 'Validate image failed: \[PublicKeyVerifier { key: ECDSA_P256_SHA256_ASN1'
}


@test "$test_tag Test pull an unencrypted unsigned image from an authenticated registry with correct credentials" {
	if [ "${AA_KBC}" = "offline_fs_kbc" ]; then
		setup_credentials_files "quay.io/kata-containers/confidential-containers-auth"
	elif [ "${AA_KBC}" = "cc_kbc" ]; then
		# CC KBC is specified as: cc_kbc::http://host_ip:port/, and 60000 is the default port used
		# by the service, as well as the one configured in the Kata Containers rootfs.
		CC_KBS_IP=${CC_KBS_IP:-"$(hostname -I | awk '{print $1}')"}
		CC_KBS_PORT=${CC_KBS_PORT:-"60000"}
		add_kernel_params "agent.aa_kbc_params=cc_kbc::http://${CC_KBS_IP}:${CC_KBS_PORT}/"
	fi

	pod_config="$(new_pod_config "${image_authenticated}")"
	echo $pod_config

	create_test_pod
}

@test "$test_tag Test cannot pull an image from an authenticated registry with incorrect credentials" {
	if [ "${AA_KBC}" = "cc_kbc" ]; then
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
	teardown_common
}
