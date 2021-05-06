#
# Copyright (c) 2021 Red Hat, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
# This script is evoked within an OpenShift Build to product the binary image,
# which will contain the Kata Containers installation into a given destination
# directory.
#
# This contains variables and functions common to all e2e tests.

get_pod_config_dir() {
	pod_config_dir="${BATS_TEST_DIRNAME}/runtimeclass_workloads"
	info "k8s configured to use runtimeclass"
}

# Uses crictl to pull a container image passed in $1.
# If crictl is not found then it just prints a warning.
crictl_pull() {
	local img="${1:-}"
	local cmd="crictl"
	if ! command -v "$cmd" &>/dev/null; then
		warn "$cmd not found. Cannot pull image $img"
	else
		sudo -E "$cmd" pull "$img"
	fi
}
