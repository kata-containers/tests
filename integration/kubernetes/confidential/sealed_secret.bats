#!/usr/bin/env bats
# Copyright (c) 2023 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

load "${BATS_TEST_DIRNAME}/lib.sh"
load "${BATS_TEST_DIRNAME}/../../confidential/lib.sh"
load "${BATS_TEST_DIRNAME}/../../../lib/common.bash"

# Allow to configure the runtimeClassName on pod configuration.
RUNTIMECLASS="${RUNTIMECLASS:-kata}"
test_tag="[cc][agent][kubernetes][containerd]"
original_kernel_params=$(get_kernel_params)

setup() {
    start_date=$(date +"%Y-%m-%d %H:%M:%S")

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

    kubectl delete secret sealed-secret --ignore-not-found
    # Sealed secret format is defined at: https://github.com/confidential-containers/guest-components/blob/main/confidential-data-hub/docs/SEALED_SECRET.md#vault
    # sealed.BASE64URL(UTF8(JWS Protected Header)) || '.
    # || BASE64URL(JWS Payload) || '.'
    # || BASE64URL(JWS Signature)
    # test payload:
    # {
    # "version": "0.1.0",
    # "type": "vault",
    # "name": "kbs:///default/sealed-secret/test",
    # "provider": "kbs",
    # "provider_settings": {},
    # "annotations": {}
    # }
    kubectl create secret generic sealed-secret --from-literal='password=sealed.fakejwsheader.ewogICAgInZlcnNpb24iOiAiMC4xLjAiLAogICAgInR5cGUiOiAidmF1bHQiLAogICAgIm5hbWUiOiAia2JzOi8vL2RlZmF1bHQvc2VhbGVkLXNlY3JldC90ZXN0IiwKICAgICJwcm92aWRlciI6ICJrYnMiLAogICAgInByb3ZpZGVyX3NldHRpbmdzIjoge30sCiAgICAiYW5ub3RhdGlvbnMiOiB7fQp9Cg==.fakesignature'
}

@test "$test_tag Test can use KBS to unseal secret as environment or volume file" {
    if [ "${AA_KBC}" = "offline_fs_kbc" ]; then
        setup_offline_fs_kbc_secret_files_in_guest
    elif [ "${AA_KBC}" = "cc_kbc" ]; then
        # CC KBC is specified as: cc_kbc::http://host_ip:port/, and 60000 is the default port used
        # by the service, as well as the one configured in the Kata Containers rootfs.
	CC_KBS_IP=${CC_KBS_IP:-"$(hostname -I | awk '{print $1}')"}
	CC_KBS_PORT=${CC_KBS_PORT:-"60000"}
	add_kernel_params "agent.aa_kbc_params=cc_kbc::http://${CC_KBS_IP}:${CC_KBS_PORT}/"
    fi

    local base_config="${FIXTURES_DIR}/pod-config-secret.yaml.in"

    local pod_config=$(mktemp "${BATS_FILE_TMPDIR}/$(basename ${base_config}).XXX")
    RUNTIMECLASS="$RUNTIMECLASS" envsubst \$RUNTIMECLASS < "$base_config" > "$pod_config"
    echo "$pod_config"

    kubernetes_create_cc_pod $pod_config

    # Wait 5s for connecting with remote KBS to unseal secret
    sleep 5

    kubectl logs secret-test-pod-cc
    kubectl logs secret-test-pod-cc | grep -q "unsealed environment as expected"
    kubectl logs secret-test-pod-cc | grep -q "unsealed volume as expected"
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

    kubernetes_delete_all_cc_pods_if_any_exists || true
    kubectl delete secret sealed-secret --ignore-not-found

    clear_kernel_params
    add_kernel_params "${original_kernel_params}"
    switch_image_service_offload off
    disable_full_debug
}
