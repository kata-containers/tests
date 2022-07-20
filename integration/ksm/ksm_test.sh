#!/bin/bash
#
# Copyright (c) 2019,2021 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#
# This will run two containers and will wait
# to the KSM to settle down and then it will
# check that the merged pages count is
# increasing

set -e

dir_path=$(dirname "$0")
source "${dir_path}/../../lib/common.bash"
source "${dir_path}/../../metrics/lib/common.bash"
source "/etc/os-release" || source "/usr/lib/os-release"

KATA_KSM_THROTTLER="${KATA_KSM_THROTTLER:-yes}"
PAYLOAD_ARGS="${PAYLOAD_ARGS:-tail -f /dev/null}"
IMAGE="${IMAGE:-quay.io/prometheus/busybox:latest}"
WAIT_TIME="60"

issue="https://github.com/kata-containers/tests/issues/4922"
if [ "${NAME}" == "Ubuntu" ] && [ "$(echo "${VERSION_ID} >= 22.04" | bc -q)" == "1" ]; then
	echo "Skip ksm test is not working with cgroupsv2 see $issue"
	exit 0
fi
function setup() {
	restart_containerd_service
	check_processes
	save_ksm_settings
	set_ksm_aggressive
}

function teardown() {
	clean_env_ctr
	check_processes
	restore_ksm_settings
}

trap teardown EXIT

function run_with_ksm() {
	setup

	sudo ctr image pull "${IMAGE}"

	# Running the first container
	sudo ctr run -d --runtime="${CTR_RUNTIME}" "${IMAGE}" test  sh -c "${PAYLOAD_ARGS}"

	echo "Entering KSM settle mode on first container"
	wait_ksm_settle "${WAIT_TIME}"

	# Checking the pages merged for the first container
	first_pages_merged=$(cat "${KSM_PAGES_SHARED}")

	echo "Pages merged $first_pages_merged"

	# Running the second container
	sudo ctr run -d --runtime="${CTR_RUNTIME}" "${IMAGE}" test1  sh -c "${PAYLOAD_ARGS}"

	echo "Entering KSM settle mode on second container"
	wait_ksm_settle "${WAIT_TIME}"

	# Checking the pages merged for the second container
	second_pages_merged=$(cat "${KSM_PAGES_SHARED}")

	echo "Pages merged $second_pages_merged"

	# Compared the pages merged between the containers
	echo "Comparing merged pages between containers"
	[ "$second_pages_merged" -ge "$first_pages_merged" ] || die "The merged pages on the second container is less than the first container"

}

echo "Starting KSM test"
run_with_ksm
