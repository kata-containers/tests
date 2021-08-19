#!/bin/bash
#
# Copyright (c) 2020-2021 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#
# This will enable the sandbox_cgroup_only
# to true in order to test that ctr is
# working properly when this feature is
# enabled

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

dir_path=$(dirname "$0")
source "${dir_path}/../../lib/common.bash"
source "${dir_path}/../../.ci/lib.sh"
tests_repo="${tests_repo:-github.com/kata-containers/tests}"
TEST_SANDBOX_CGROUP_ONLY="${TEST_SANDBOX_CGROUP_ONLY:-}"

if [ -z "${TEST_SANDBOX_CGROUP_ONLY}" ]; then
	info "Skip: TEST_SANDBOX_CGROUP_ONLY variable is not set"
	exit 0
fi

function setup() {
	restart_containerd_service
	check_processes
}

function test_stability() {
	pushd "${GOPATH}/src/${tests_repo}"
	".ci/set_kata_config.sh" sandbox_cgroup_only true
	sudo -E PATH="$PATH" bash -c "make stability"
	".ci/set_kata_config.sh" sandbox_cgroup_only false
	popd
}

function teardown() {
	clean_env_ctr
	check_processes
}

trap teardown EXIT

echo "Running setup"
setup

echo "Running stability integration tests with sandbox cgroup enabled"
test_stability
