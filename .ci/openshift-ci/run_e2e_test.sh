#!/bin/bash
#
# Copyright (c) 2020 Red Hat, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
# Run the OpenShift e2e conformance tests.
#
set -e

script_dir="$(dirname $0)"
tests_dir="$script_dir/../../"

# The test cluster will be configured to run the tests.
export CI="true"

pushd "$tests_dir"
make openshift-e2e
popd
