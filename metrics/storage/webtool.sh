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
CI_JOB="${CI_JOB:-""}"
configuration_file="/usr/share/defaults/kata-containers/configuration.toml"
# Directory to run the test on
# This is run inside of the container
TESTDIR="${TESTDIR:-/testdir}"
file_path="/web-tooling-benchmark/"
file_name="output"
CMD="mkdir -p ${TESTDIR}; cd $file_path && node dist/cli.js > $file_name"
http_proxy="${http_proxy:-}"
https_proxy="${https_proxy:-}"
NUM_CONTAINERS="$1"
# This timeout is related with the amount of time that
# webtool benchmark needs to run inside the container
timeout=$((180 * "$NUM_CONTAINERS"))
# This timeout is related with the amount of time that
# is needed to launch a container - Up status
timeout_running=$((2 * "$NUM_CONTAINERS"))
declare -a CONTAINERS_ID

TMP_DIR=$(mktemp --tmpdir -d webtool.XXXXXXXXXX)

remove_tmp_dir() {
	rm -rf "$TMP_DIR"
}

trap remove_tmp_dir EXIT

# Show help about this script
help(){
cat << EOF
Usage: $0 <count>
   Description:
	<count> : Number of containers to run.
EOF
}

save_config(){
	metrics_json_start_array

	local json="$(cat << EOF
	{
		"containers": "$NUM_CONTAINERS",
		"image": "$IMAGE",
		"units": "runs/s"
	}
EOF
)"
	metrics_json_add_array_element "$json"
	metrics_json_end_array "Config"
}


function main() {
	# Verify enough arguments
	if [ $# != 1 ]; then
		echo >&2 "error: Not enough arguments [$@]"
		help
		exit 1
	fi

	containers=()
	# Check tools/commands dependencies
	cmds=("docker")

	init_env
	check_cmds "${cmds[@]}"
	check_dockerfiles_images "$IMAGE" "$DOCKERFILE"

	metrics_json_init

	save_config

	for ((i=1; i<= "$NUM_CONTAINERS"; i++)); do
	containers+=($(random_name))
		# Web tool benchmark needs 2 cpus to run completely in its cpu utilization
		docker run --cpus=2 --env http_proxy="$http_proxy" --env https_proxy="$https_proxy" --name "${containers[-1]}" -tid --runtime="$RUNTIME" "$IMAGE" bash -c ''"$CMD"''
	done

	# We verify that number of containers that we selected
	# are running
	for i in $(seq "$timeout_running") ; do
		echo "Verify that the containers are running"
		containers_launched=$(docker ps -a | grep "$IMAGE" | grep "Up" | wc -l)
		if [ "$containers_launched" -eq "$NUM_CONTAINERS" ]; then
			break
		fi
		sleep 1
		[ "$i" == "$timeout" ] && return 1
	done

	# Now that containers were launched, we need to verify that they finished
	# running the webtootl benchmark
	for i in $(seq "$timeout") ; do
		echo "Verify that the containers are exited"
		containers_exited=$(docker ps -a | grep "$IMAGE" | grep "Exited" | wc -l)
		if [ "$containers_exited" -eq "$NUM_CONTAINERS" ]; then
			break
		fi
		sleep 1
		[ "$i" == "$timeout" ] && return 1
	done

	# Get container's ids
	CONTAINERS_ID=($(docker ps -a --format "table {{.ID}}" | tail -n +2))
	for i in "${CONTAINERS_ID[@]}"; do
		docker cp "$i:$file_path/$file_name" "$TMP_DIR"
		pushd "$TMP_DIR"
		cat "$file_name" >> "results"
		popd
	done

	# Save configuration
	metrics_json_start_array

	local output=$(cat "$TMP_DIR/results")
	local cut_results="cut -d':' -f2 | sed -e 's/^[ \t]*//'| cut -d ' ' -f1 | tr '\n' ',' | sed 's/.$//'"

	local acorn=$(echo "$output" | grep -w "acorn" | eval "${cut_results}")
	local babel=$(echo "$output" | grep -w "babel" | sed '/babel-minify/d' | eval "${cut_results}")
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
	local tps=$(echo "$geometric_mean" | sed "s/,/+/g;s/.*/(&)\/$NUM_CONTAINERS/g" | bc -l)
	local total_tps=$(echo "$average_tps*$NUM_CONTAINERS" | bc -l)

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
		"Geometric mean" : "$geometric_mean",
		"TPS" : "$tps",
		"Total TPS" : "$total_tps"
	}
EOF
)"
	metrics_json_add_array_element "$json"
	metrics_json_end_array "Results"
	metrics_json_save
	docker rm -f ${containers[@]}
	clean_env
}

main "$@"
