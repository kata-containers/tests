#!/bin/bash
#
# Copyright (c) 2020-2021 Intel Corporation
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
IMAGE="docker.io/library/local-web-tooling:latest"
DOCKERFILE="${SCRIPT_PATH}/web-tooling-dockerfile/Dockerfile"
CI_JOB="${CI_JOB:-""}"
configuration_file="/usr/share/defaults/kata-containers/configuration.toml"
# Directory to run the test on
# This is run inside of the container
TESTDIR="${TESTDIR:-/testdir}"
file_path="/web-tooling-benchmark"
file_name="output"
CMD="mkdir -p ${TESTDIR}; cd $file_path && node dist/cli.js > $file_name"
PAYLOAD_ARGS="${PAYLOAD_ARGS:-tail -f /dev/null}"
NUM_CONTAINERS="$1"
# This timeout is related with the amount of time that
# webtool benchmark needs to run inside the container
timeout=$((180 * "$NUM_CONTAINERS"))
declare -a CONTAINERS_ID
cpu_period="100000"
cpu_quota="200000"

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
	cmds=()
	cmds+=("docker")

	sudo systemctl restart containerd
	init_env
	check_cmds "${cmds[@]}"
	check_ctr_images "$IMAGE" "$DOCKERFILE"

	metrics_json_init

	save_config

	for ((i=1; i<= "$NUM_CONTAINERS"; i++)); do
		containers+=($(random_name))
		# Web tool benchmark needs 2 cpus to run completely in its cpu utilization
		sudo -E ctr run -d --runtime io.containerd.run.kata.v2 --cpu-quota "${cpu_quota}" --cpu-period "${cpu_period}" "$IMAGE" "${containers[-1]}" sh -c "$PAYLOAD_ARGS"
	done

	# We verify that number of containers that we selected
	# are running
	for i in $(seq "$timeout") ; do
		echo "Verify that the containers are running"
		containers_launched=$(sudo ctr c list -q | wc -l)
		[ "$containers_launched" -eq "$NUM_CONTAINERS" ] && break
 		sleep 1
 		[ "$i" == "$timeout" ] && return 1
	done

	# Launch webtooling benchmark
 	CONTAINERS_ID=($(sudo ctr c list -q))
 	for i in "${CONTAINERS_ID[@]}"; do
		sudo ctr t exec -d --exec-id "$(random_name)" "$i" sh -c "$CMD"
 	done

	# Verify that webtooling benchmark finished
	CONTAINERS_ID=($(sudo ctr c list -q))
	for i in $(seq 1 "$timeout"); do
 		FILE_CMD="cat $file_path/$file_name | grep Geometric"
 		check_file_content=$(sudo ctr t exec --exec-id "$(random_name)" "$i" sh -c "$FILE_CMD")
		[ ! -z "$check_file_content" ] && break
 		sleep 1
	done

	# Copy the results from the container
	RESULTS_CMD="cat $file_path/$file_name"
	CONTAINERS_ID=($(sudo ctr c list -q))
	for i in "${CONTAINERS_ID[@]}"; do
		sudo ctr t exec --exec-id "$(random_name)" "$i" sh -c "$RESULTS_CMD" >> "$TMP_DIR"/results
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
	local total_tps=$(echo "$tps*$NUM_CONTAINERS" | bc -l)

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
	sudo ctr tasks rm -f $(sudo ctr task list -q)
	sudo ctr c rm $(sudo ctr c list -q)
}

main "$@"
