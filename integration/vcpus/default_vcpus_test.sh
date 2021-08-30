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
KATA_HYPERVISOR="${KATA_HYPERVISOR:-qemu}"
name="${name:-default_vcpus}"
IMAGE="${IMAGE:-quay.io/prometheus/busybox:latest}"
CONTAINER_NAME="${CONTAINER_NAME:-test}"
PAYLOAD_ARGS="${PAYLOAD_ARGS:-nproc | grep 4}"
RUNTIME_CONFIG_PATH="${RUNTIME_CONFIG_PATH:-}"
TEST_INITRD="${TEST_INITRD:-no}"
issue="github.com/kata-containers/tests/issues/3303"

if [ "$TEST_INITRD" == "yes" ]; then
	echo "Skip vcpu test is not working $issue"
	exit 0
fi

function setup() {
	restart_containerd_service
	check_processes
	extract_kata_env
	sudo sed -i "s/${name} = 1/${name} = 4/g" "${RUNTIME_CONFIG_PATH}"
}

function test_ctr_with_vcpus() {
	CONTAINERD_RUNTIME="io.containerd.kata.v2"
	sudo ctr image pull "${IMAGE}"
	[ $? != 0 ] && die "Unable to get image $IMAGE"
	sudo ctr run --runtime="${CONTAINERD_RUNTIME}" -d "${IMAGE}" "${CONTAINER_NAME}" sh -c "${PAYLOAD_ARGS}"
}

function teardown() {
	sudo sed -i "s/${name} = 4/${name} = 1/g" "${RUNTIME_CONFIG_PATH}"
	sudo ctr tasks rm -f $(sudo ctr task list -q)
	sudo ctr c rm $(sudo ctr c list -q)
	clean_env_ctr
	check_processes
}

trap teardown EXIT

echo "Running setup"
setup

echo "Running ctr integration tests with vcpus"
test_ctr_with_vcpus
