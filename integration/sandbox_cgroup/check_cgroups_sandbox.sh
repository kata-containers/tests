#!/bin/bash
#
# Copyright (c) 2020 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#
# This will enable the sandbox_cgroup_only
# to true and verify the cgroups

dir_path=$(dirname "$0")
source "${dir_path}/../../lib/common.bash"
source "${dir_path}/../../.ci/lib.sh"
tests_repo="${tests_repo:-github.com/kata-containers/tests}"
TEST_SANDBOX_CGROUP_ONLY="${TEST_SANDBOX_CGROUP_ONLY:-}"
image="centos"
container_name="test_cgroups"
payload="tail -f /dev/null"
docker_cgroup_prefix="/sys/fs/cgroup/devices/docker"

if [ -z "${TEST_SANDBOX_CGROUP_ONLY}" ]; then
	info "Skip: TEST_SANDBOX_CGROUP_ONLY variable is not set"
	exit 0
fi

if ! command -v docker >/dev/null; then
	info "This test needs docker to run"
	exit 1
fi

function setup() {
	clean_env
	check_processes
}

function check_cgroups_sandbox() {
	pushd "${GOPATH}/src/${tests_repo}"
	".ci/toggle_sandbox_cgroup_only.sh" true
	docker run -d --name "${container_name}" --runtime "${RUNTIME}" "${image}" sh -c "${payload}"
	get_id=$(docker inspect --format='{{.Id}}' "${container_name}")
	# Verify first cgroup
	first_cgroup="a *.* rwm"
	check_first_cgroup=$(grep -Fx "${first_cgroup}" "${docker_cgroup_prefix}"/kata_"${get_id}"/devices.list)
	if [ ! -z "${check_first_cgroup}" ]; then
		echo "${first_cgroup} should not be there"
		exit 1
	fi

	# Verify second cgroup
	second_cgroup="c *:* rwm"
	check_second_cgroup=$(grep -Fx "${second_cgroup}" "${docker_cgroup_prefix}"/kata_"${get_id}"/devices.list)
	if [ ! -z "${check_second_cgroup}" ]; then
		echo "${second_cgroup} should not be there"
		exit 1
	fi

	# Verify third cgroup
	third_cgroup="b *:* rwm"
	check_third_cgroup=$(grep -Fx "${third_cgroup}" "${docker_cgroup_prefix}"/kata_"${get_id}"/devices.list)
	if [ ! -z "${check_third_cgroup}" ]; then
		echo "${third_cgroup} should not be there"
		exit 1
	fi
	popd
}

function teardown() {
	pushd "${GOPATH}/src/${tests_repo}"
	".ci/toggle_sandbox_cgroup_only.sh" false
	popd
	docker rm -f "${container_name}"
	clean_env
	check_processes
}

trap teardown EXIT

echo "Running setup"
setup

echo "Running check cgroups sandbox"
check_cgroups_sandbox
