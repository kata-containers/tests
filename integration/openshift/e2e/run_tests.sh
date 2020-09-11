#!/bin/bash
#
# Copyright (c) 2020 Red Hat, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
set -e

source /etc/os-release || source /usr/lib/os-release
script_dir="$(realpath $(dirname $0))"
source "$script_dir/../../../lib/common.bash"
CI=${CI:-false}

readonly runner="${script_dir}/runner.sh"
runner_args=""
output_dir="${KATA_TESTS_BASEDIR}/openshift-e2e"

info "Run OpenShift e2e tests"

if [ "$CI" == "true" ]; then
	info "CI mode on. Configure the OpenShift cluster."
	runner_args+=" -c"
else
	output_dir="$(mktemp -d)"
fi

runner_args+=" -o ${output_dir}"
info "Test output directory is ${output_dir}"

"$runner" $runner_args
