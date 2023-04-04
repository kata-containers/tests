#!/bin/bash
#
# Copyright (c) 2023 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

set -e

# General env
SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_PATH}/../lib/common.bash"

TEST_NAME="tensorflow"
IMAGE="docker.io/library/tensorflow:latest"
DOCKERFILE="${SCRIPT_PATH}/tensorflow_dockerfile/Dockerfile"
CMD="cd benchmarks/scripts/tf_cnn_benchmarks/ && python tf_cnn_benchmarks.py -data_format=NHWC --device cpu --batch_size 512 --num_batches=300"
tensorflow_file=$(mktemp tensorflowresults.XXXXXXXXXX)

function remove_tmp_file() {
	rm -rf "${tensorflow_file}"
}

trap remove_tmp_file EXIT

function main() {
	# Check tools/commands dependencies
	cmds=("awk" "docker")
	init_env
	check_cmds "${cmds[@]}"
	check_ctr_images "${IMAGE}" "${DOCKERFILE}"
	sudo -E "${CTR_EXE}" run --rm --runtime="${CTR_RUNTIME}" "${IMAGE}" test sh -c "${CMD}" > "${tensorflow_file}"
	results=$(cat "${tensorflow_file}" | grep "total images/sec" | cut -d ":" -f2 | sed -e 's/^[ \t]*//')
	metrics_json_init
	metrics_json_start_array
	local json="$(cat << EOF
	{
		"NHWC": {
			"Result": ${results},
			"Units": "s"
		}
	}
EOF
)"
	metrics_json_add_array_element "$json"
	metrics_json_end_array "Results"
	metrics_json_save

	clean_env_ctr
}

main "$@"
