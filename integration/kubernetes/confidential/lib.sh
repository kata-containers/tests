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

# Toggle between true and false the service_offload configuration of
# the Kata agent.
#
# Parameters:
#	$1: "on" to activate the service, or "off" to turn it off.
#
# Environment variables:
#	RUNTIME_CONFIG_PATH - path to kata's configuration.toml. If it is not
#			      export then it will figure out the path via
#			      `kata-runtime env` and export its value.
#
switch_image_service_offload() {
	# Load the RUNTIME_CONFIG_PATH variable.
	load_RUNTIME_CONFIG_PATH

	case "$1" in
		"on")
			sudo sed -i -e 's/^# *\(service_offload\).*=.*$/\1 = true/g' \
				"$RUNTIME_CONFIG_PATH"
			;;
		"off")
			sudo sed -i -e 's/^\(service_offload\).*=.*$/#\1 = false/g' \
				"$RUNTIME_CONFIG_PATH"

			;;
		*)
			echo "Unknown option $1"
			return 1
			;;
	esac
}

# Add parameters to the 'kernel_params' property on kata's configuration.toml
#
# Parameters:
#	$1..$N - list of parameters
#
# Environment variables:
#	RUNTIME_CONFIG_PATH - path to kata's configuration.toml. If it is not
#			      export then it will figure out the path via
#			      `kata-runtime env` and export its value.
#
add_kernel_params() {
	local params="$@"
	load_RUNTIME_CONFIG_PATH

	sudo sed -i -e 's#^\(kernel_params\) = "\(.*\)"#\1 = "\2 '"$params"'"#g' \
		"$RUNTIME_CONFIG_PATH"
}

# Clear the 'kernel_params' property on kata's configuration.toml
#
# Environment variables:
#	RUNTIME_CONFIG_PATH - path to kata's configuration.toml. If it is not
#			      export then it will figure out the path via
#			      `kata-runtime env` and export its value.
#
clear_kernel_params() {
	load_RUNTIME_CONFIG_PATH

	sudo sed -i -e 's#^\(kernel_params\) = "\(.*\)"#\1 = ""#g' \
		"$RUNTIME_CONFIG_PATH"
}

# Enable the agent console so that one can open a shell with the guest VM.
#
# Environment variables:
#	RUNTIME_CONFIG_PATH - path to kata's configuration.toml. If it is not
#			      export then it will figure out the path via
#			      `kata-runtime env` and export its value.
#
enable_agent_console() {
	load_RUNTIME_CONFIG_PATH

	sudo sed -i -e 's/^# *\(debug_console_enabled\).*=.*$/\1 = true/g' \
		"$RUNTIME_CONFIG_PATH"
}

enable_full_debug() {
	# Load the RUNTIME_CONFIG_PATH variable.
	load_RUNTIME_CONFIG_PATH

	# Toggle all the debug flags on in kata's configuration.toml to enable full logging.
	sudo sed -i -e 's/^# *\(enable_debug\).*=.*$/\1 = true/g' "$RUNTIME_CONFIG_PATH"

	# Also pass the initcall debug flags via Kernel parameters.
	add_kernel_params "agent.log=debug" "initcall_debug"
}

disable_full_debug() {
	# Load the RUNTIME_CONFIG_PATH variable.
	load_RUNTIME_CONFIG_PATH

	# Toggle all the debug flags off in kata's configuration.toml to enable full logging.
	sudo sed -i -e 's/^# *\(enable_debug\).*=.*$/\1 = false/g' "$RUNTIME_CONFIG_PATH"
}


# Auxiliar functions.


# Export the RUNTIME_CONFIG_PATH variable if it not set already.
#
load_RUNTIME_CONFIG_PATH() {
	if [ -z "$RUNTIME_CONFIG_PATH" ]; then
		extract_kata_env
	fi
}

# Retrieve the sandbox ID 
#
retrieve_sandbox_id() {
	sandbox_id=$(ps -ef | grep containerd-shim-kata-v2 | egrep -o "id [^,][^,].* " | awk '{print $2}')
}
