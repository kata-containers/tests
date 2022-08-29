#!/bin/bash
# Copyright (c) 2021, 2022 IBM Corporation
# Copyright (c) 2022 Red Hat
#
# SPDX-License-Identifier: Apache-2.0
#
# This provides generic functions to use in the tests.
#
set -e

source "${BATS_TEST_DIRNAME}/../../../lib/common.bash"
FIXTURES_DIR="${BATS_TEST_DIRNAME}/fixtures"

# Currently the agent can only check images signature if using skopeo.
# There isn't a way to probe the agent to determine if skopeo is present
# or not, so we need to rely on build variables. If we are running under
# CI then we assume the variables are properly exported, otherwise we
# should skip testing.
#
skip_if_skopeo_not_present () {
	if [ "${CI:-}" == "true" ]; then
		if [ "${SKOPEO:-no}" == "no" ]; then
			skip "Skopeo seems not installed in guest"
		fi
	else
		skip "Cannot determine skopeo is installed in guest"
	fi
}

# Delete the containers alongside the Pod.
#
# Parameters:
#	$1 - the sandbox name
#
kubernetes_delete_cc_pod() {
	local sandbox_name="$1"
	local pod_id=${sandbox_name}
	if [ -n "${pod_id}" ]; then
	
		kubectl delete pod "${pod_id}"
	fi
}

# Delete the pod if it exists, otherwise just return.
#
# Parameters:
#	$1 - the sandbox name
#
kubernetes_delete_cc_pod_if_exists() {
	local sandbox_name="$1"
	[ -z "$(kubectl get pods ${sandbox_name})" ] || \
		kubernetes_delete_cc_pod "${sandbox_name}"
}

# Wait until the pod is not 'Ready'. Fail if it hits the timeout.
#
# Parameters:
#	$1 - the sandbox ID
#	$2 - wait time in seconds. Defaults to 60. (optional)
#	$3 - sleep time in seconds between checks. Defaults to 5. (optional)
#
kubernetes_wait_cc_pod_be_ready() {
	local pod_name="$1"
	local wait_time="${2:-60}"

	kubectl wait --timeout=${wait_time}s --for=condition=ready pods/$pod_name
}

# Create a pod and wait it be ready, otherwise fail.
#
# Parameters:
#	$1 - the pod configuration file.
#
kubernetes_create_cc_pod() {
	local config_file="$1"
	local pod_name=""

	if [ ! -f "${config_file}" ]; then
		echo "Pod config file '${config_file}' does not exist"
		return 1
	fi

	kubectl apply -f ${config_file}
	if ! pod_name=$(kubectl get pods -o jsonpath='{.items..metadata.name}'); then
		echo "Failed to create the pod"
		return 1
	fi

	if ! kubernetes_wait_cc_pod_be_ready "$pod_name"; then
		# TODO: run this command for debugging. Maybe it should be
		#       guarded by DEBUG=true?
		kubectl get pods "$pod_name"
		return 1
	fi
}

# Retrieve the sandbox ID 
#
retrieve_sandbox_id() {
	sandbox_id=$(ps -ef | grep containerd-shim-kata-v2 | egrep -o "id [^,][^,].* " | awk '{print $2}')
}

# Check out the doc repo if required
checkout_doc_repo_dir() {
    local doc_repo=github.com/confidential-containers/documentation
    export doc_repo_dir="${GOPATH}/src/${doc_repo}"    
    mkdir -p $(dirname ${doc_repo_dir}) && sudo chown -R ${USER}:${USER} $(dirname ${doc_repo_dir})
    if [ ! -d "${doc_repo_dir}" ]; then
        git clone https://${doc_repo} "${doc_repo_dir}"
        # Update runtimeClassName from kata-cc to kata
        sudo sed -i -e 's/\([[:blank:]]*runtimeClassName: \).*/\1kata/g' "${doc_repo_dir}/demos/ssh-demo/k8s-cc-ssh.yaml"
        chmod 600 ${doc_repo_dir}/demos/ssh-demo/ccv0-ssh
    fi
}

kubernetes_create_ssh_demo_pod() {
	checkout_doc_repo_dir
	kubectl apply -f "${doc_repo_dir}/demos/ssh-demo/k8s-cc-ssh.yaml" && pod=$(kubectl get pods -o jsonpath='{.items..metadata.name}') && kubectl wait --timeout=60s --for=condition=ready pods/$pod
	kubectl get pod $pod
}

connect_to_ssh_demo_pod() {
	local doc_repo=github.com/confidential-containers/documentation
	local doc_repo_dir="${GOPATH}/src/${doc_repo}"    
	local ssh_command="ssh -i ${doc_repo_dir}/demos/ssh-demo/ccv0-ssh root@$(kubectl get service ccv0-ssh -o jsonpath="{.spec.clusterIP}")"
	echo "Issuing command '${ssh_command}'"
	${ssh_command}
}

kubernetes_delete_ssh_demo_pod_if_exists() {
	local sandbox_name="$1"
	if [ -n "$(kubectl get pods $sandbox_name)" ]; then
		kubernetes_delete_ssh_demo_pod ${sandbox_name}
	fi
}

kubernetes_delete_ssh_demo_pod() {
	checkout_doc_repo_dir
	kubectl delete -f "${doc_repo_dir}/demos/ssh-demo/k8s-cc-ssh.yaml"
	kubectl wait pod/$1 --for=delete --timeout=-30s
}

assert_pod_fail() {
	local container_config="$1"
	echo "In assert_pod_fail: "$container_config

	echo "Attempt to create the container but it should fail"
	! kubernetes_create_cc_pod "$container_config" || /bin/false
}

setup_decryption_files_in_guest() {
    local rootfs_agent_config="/etc/agent-config.toml"
    sudo -E AA_KBC_PARAMS="offline_fs_kbc::null" HTTPS_PROXY="${HTTPS_PROXY:-${https_proxy:-}}" envsubst < ${katacontainers_repo_dir}/docs/how-to/data/confidential-agent-config.toml.in | sudo tee ${rootfs_agent_config}
	
    cp_to_guest_img "/tests/fixtures" "${rootfs_agent_config}"
    add_kernel_params \
	    "agent.config_file=/tests/fixtures/$(basename ${rootfs_agent_config})"

    curl -Lo "${HOME}/aa-offline_fs_kbc-keys.json" https://raw.githubusercontent.com/confidential-containers/documentation/main/demos/ssh-demo/aa-offline_fs_kbc-keys.json
    cp_to_guest_img "etc" "${HOME}/aa-offline_fs_kbc-keys.json" 
}
