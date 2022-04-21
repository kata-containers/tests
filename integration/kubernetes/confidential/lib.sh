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
#	$2 - wait time in seconds. Defaults to 10. (optional)
#	$3 - sleep time in seconds between checks. Defaults to 5. (optional)
#
kubernetes_wait_cc_pod_be_ready() {
	local pod_name="$1"
	local wait_time="${2:-30}"

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
