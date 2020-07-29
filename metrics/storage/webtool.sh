#!/bin/bash
#
# Copyright (c) 2020 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

# Description of the test:
# This test runs the 'web tooling benchmark'
# https://github.com/v8/web-tooling-benchmark

set -e

# General env
SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_PATH}/../lib/common.bash"

TEST_NAME="web-tooling"
IMAGE="local-web-tooling"
DOCKERFILE="${SCRIPT_PATH}/web-tooling_dockerfile/Dockerfile"
CI_JOB=${CI_JOB:-""}
configuration_file="/usr/share/defaults/kata-containers/configuration.toml"
# Directory to run the test on
# This is run inside of the container
TESTDIR="${TESTDIR:-/testdir}"
CMD="mkdir -p ${TESTDIR}; cd web-tooling-benchmark/ && node dist/cli.js"
http_proxy="${http_proxy:-}"
https_proxy="${https_proxy:-}"

function main() {
	# Check tools/commands dependencies
	cmds=("docker")

 	init_env
	check_cmds "${cmds[@]}"
	check_dockerfiles_images "$IMAGE" "$DOCKERFILE"

	metrics_json_init
	local output=$(docker run --env http_proxy=$http_proxy --env https_proxy=$https_proxy --rm --runtime=$RUNTIME $IMAGE bash -c ''"$CMD"'')

	# Save configuration
	metrics_json_start_array

	local cut_results="cut -d':' -f2 | sed -e 's/^[ \t]*//'"

	local acorn=$(echo "$output" | grep -w "acorn" | eval "${cut_results}")
	local babel=$(echo "$output" | grep -w "babel" | head -1 | eval "${cut_results}")
	local babel_minify=$(echo "$output" | grep -w "babel-minify" | eval "${cut_results}")
	local babylon=$(echo "$output" | grep -w "babylon" | eval "${cut_results}")
	local buble=$(echo "$output" | grep -w "buble" | eval "${cut_results}")
	local chai=$(echo "$output" | grep -w "chai" | eval "${cut_results}")
	local coffeescript=$(echo "$output" | grep -w "coffeescript" | eval "${cut_results}")
	local espree=$(echo "$output" | grep -w "espree" | eval "${cut_results}")
	local esprima=$(echo "$output" | grep -w "esprima" | eval "${cut_results}")
	local jshint=$(echo "$output" | grep -w "jshint" | eval "${cut_results}")
	local lebab=$(echo "$output" | grep -w "lebab" | eval "${cut_results}")
	local postcss=$(echo "$output" | grep -w "postcss" | eval "${cut_results}")
	local prepack=$(echo "$output" | grep -w "prepack" | eval "${cut_results}")
	local prettier=$(echo "$output" | grep -w "prettier" | eval "${cut_results}")
	local source_map=$(echo "$output" | grep -w "source-map" | eval "${cut_results}")
	local terser=$(echo "$output" | grep -w "terser" | eval "${cut_results}")
	local typescript=$(echo "$output" | grep -w "typescript" | eval "${cut_results}")
	local uglify_js=$(echo "$output" | grep -w "uglify-js" | eval "${cut_results}")
	local geometric_mean=$(echo "$output" | grep -w "Geometric" | eval "${cut_results}")

	local json="$(cat << EOF
	{
 		"Acorn" : "$acorn",
 		"Babel" : "$babel",
		"Babel minify" : "$babel_minify",
		"Babylon" : "$babylon",
		"Buble" : "$buble",
		"Chai" : "$chai",
		"Coffeescript" : "$coffeescript",
		"Espree" : "$espree",
		"Esprima" : "$esprima",
		"Jshint" : "$jshint",
		"Lebab" : "$lebab",
		"Postcss" : "$postcss",
		"Prepack" : "$prepack",
		"Prettier" : "$prettier",
		"Source map" : "$source_map",
		"Terser" : "$terser",
		"Typescript" : "$typescript",
		"Uglify js" : "$uglify_js",
		"Geometric mean" : "$geometric_mean"
	}
EOF
)"
	metrics_json_add_array_element "$json"
	metrics_json_end_array "Results"
	metrics_json_save
	clean_env
}

main "$@"
