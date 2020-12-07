#!/bin/bash
#
# Copyright (c) 2020 Red Hat, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#

script_dir=$(dirname $0)
source ${script_dir}/../lib.sh

# Make oc and kubectl visible
export PATH=/tmp/shared:$PATH

oc version || die "Test cluster is unreachable"

info "Install and configure kata into the test cluster"
${script_dir}/cluster/install_kata.sh || die "Failed to install kata-containers"

# Note: let the smoke tests run first and, if failed, do not run the others.
for suite in "smoke" "e2e"; do
	info "Run test suite: $suite"
	test_status='PASS'
	${script_dir}/run_${suite}_test.sh || test_status='FAIL'
	info "Test suite: $suite: $test_status"
	[ "$test_status" == "FAIL" ] && exit 1
done
