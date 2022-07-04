#!/bin/bash
#
# Copyright (c) 2020-2021 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#
# This will test the default_vcpus
# feature is working properly

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

dir_path=$(dirname "$0")
source "${dir_path}/../../lib/common.bash"
source "${dir_path}/../../.ci/lib.sh"
source "/etc/os-release" || source "/usr/lib/os-release"
KATA_HYPERVISOR="${KATA_HYPERVISOR:-qemu}"
name="${name:-default_vcpus}"
IMAGE="${IMAGE:-quay.io/prometheus/busybox:latest}"
CONTAINER_NAME="${CONTAINER_NAME:-test}"
PAYLOAD_ARGS="${PAYLOAD_ARGS:-nproc | grep 4}"
RUNTIME_CONFIG_PATH="${RUNTIME_CONFIG_PATH:-}"
TEST_INITRD="${TEST_INITRD:-no}"
issue="github.com/kata-containers/tests/issues/3303"
second_issue="https://github.com/kata-containers/tests/issues/4922"

if [ "$TEST_INITRD" == "yes" ]; then
	echo "Skip vcpu test is not working $issue"
	exit 0
fi

if [ "${NAME}" == "Ubuntu" ] && [ "$(echo "${VERSION_ID} >= 22.04" | bc -q)" == "1" ]; then
	echo "Skip vcpu test is not working with cgroupsv2 see $second_issue"
	exit 0
fi

function setup() {
	restart_containerd_service
	check_processes
	extract_kata_env
	sudo sed -i "s/${name} = 1/${name} = 4/g" "${RUNTIME_CONFIG_PATH}"
}

function test_ctr_with_vcpus() {
	sudo ctr image pull "${IMAGE}"
	[ $? != 0 ] && die "Unable to get image $IMAGE"
	sudo ctr run --runtime="${CTR_RUNTIME}" -d "${IMAGE}" \
		"${CONTAINER_NAME}" sh -c "${PAYLOAD_ARGS}" || die "Test failed"
}

function teardown() {
	echo "Running teardown"
	sudo sed -i "s/${name} = 4/${name} = 1/g" "${RUNTIME_CONFIG_PATH}"
	clean_env_ctr
	check_processes
}

trap teardown EXIT

echo "Running setup"
setup

echo "Running ctr integration tests with vcpus"
test_ctr_with_vcpus
