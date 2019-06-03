#!/bin/bash
#
# Copyright (c) 2018 ARM Limited
#
# SPDX-License-Identifier: Apache-2.0

set -e

test_config_file="$1"

describe_skip_flag="docker.Describe"
context_skip_flag="docker.Context"
it_skip_flag="docker.It"

# value for '-skip' in ginkgo
_skip_options=()

GOPATH_LOCAL="${GOPATH%%:*}"
kata_dir="${GOPATH_LOCAL}/src/github.com/kata-containers"
test_dir="${kata_dir}/tests"
ci_dir="${test_dir}/.ci"
source "${ci_dir}/lib.sh"

filter_and_build()
{
	local dependency="$1"
	local array_docker=$("${GOPATH_LOCAL}/bin/yq" read "${test_config_file}" "${dependency}")
	[ "${array_docker}" = "null" ] && return
	mapfile -t _array_docker <<< "${array_docker}"
	for entry in "${_array_docker[@]}"
	do
		_skip_options+=("${entry#- }|")
	done
}

main()
{
	# install yq if not exist
	[ -z "$(command -v yq)" ] && install_yq
	# build skip option based on Describe block
	filter_and_build "${describe_skip_flag}"

	# build skip option based on context block
	filter_and_build "${context_skip_flag}"

	# build skip option based on it block
	filter_and_build "${it_skip_flag}"

	skip_options=$(IFS= ; echo "${_skip_options[*]}")

	echo "${skip_options%|}"
}

main
