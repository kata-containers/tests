#!/usr/bin/env bats
# Copyright (c) 2022 IBM
#
# SPDX-License-Identifier: Apache-2.0
#

load "${BATS_TEST_DIRNAME}/lib.sh"
load "${BATS_TEST_DIRNAME}/../../confidential/lib.sh"
load "${BATS_TEST_DIRNAME}/../../../lib/common.bash"

test_tag="[cc][agent][kubernetes][containerd]"

setup() {
    start_date=$(date +"%Y-%m-%d %H:%M:%S")

    pod_id=$(kubectl get pods -o jsonpath='{.items..metadata.name}')
    if [ -n ${pod_id} ]; then
	    kubernetes_delete_ssh_demo_pod_if_exists "$pod_id"
    fi
    
    echo "Prepare containerd for Confidential Container"
    SAVED_CONTAINERD_CONF_FILE="/etc/containerd/config.toml.$$"
    configure_cc_containerd "$SAVED_CONTAINERD_CONF_FILE"

    echo "Reconfigure Kata Containers"
    switch_image_service_offload on
    clear_kernel_params
}

@test "$test_tag Test can pull an encrypted image inside the guest with decryption key" {

    setup_decryption_files_in_guest
    kubernetes_create_ssh_demo_pod

    local pod_ip_address=$(kubectl get service ccv0-ssh -o jsonpath="{.spec.clusterIP}")
    ssh-keygen -lf <(ssh-keyscan ${pod_ip_address} 2>/dev/null)

    ssh -i ${doc_repo_dir}/demos/ssh-demo/ccv0-ssh root@${pod_ip_address} -o StrictHostKeyChecking=accept-new exit
}

@test "$test_tag Test cannot pull an encrypted image inside the guest without decryption key" {

    checkout_doc_repo_dir
    assert_pod_fail "k8s-cc-ssh.yaml" 
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

    pod_id=$(kubectl get pods -o jsonpath='{.items..metadata.name}')
    kubernetes_delete_ssh_demo_pod_if_exists "$pod_id" || true

    clear_kernel_params
    switch_image_service_offload off
    disable_full_debug
}
