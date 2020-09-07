#!/bin/bash
#
# Copyright (c) 2020 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

# Description of the test:
# This test runs the 'tensorflow benchmark'
# https://github.com/IntelAI/models/blob/master/benchmarks/image_recognition/tensorflow/resnet50v1_5/
set -e

# General env
SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_PATH}/../lib/common.bash"

TEST_NAME="tensorflow"
CI_JOB="${CI_JOB:-""}"
TMP_DIR="$(mktemp -d /tmp/resnet.XXXXXX)"
INTELAI_REPO="github.com/IntelAI/models"
MODEL="resnet50"
MODEL_VERSION="${MODEL}v1_5"
PRE_TRAINED_MODEL_FILE="${MODEL}_v1.pb"
PRE_TRAINED_MODEL="https://zenodo.org/record/2535873/files/${PRE_TRAINED_MODEL_FILE}"
DOCKER_IMAGE="intel/intel-optimized-tensorflow:2.2.0"
FRAMEWORK="tensorflow"
BATCH_SIZE="10"
PRECISION="fp32"
MODE="inference"

remove_tmp_dir() {
	rm -rf "${TMP_DIR}"
}

trap remove_tmp_dir EXIT

save_config(){
	metrics_json_start_array

	local json="$(cat << EOF
	{
		"image": "${DOCKER_IMAGE}",
		"framework": "${FRAMEWORK}",
		"batch size": "${BATCH_SIZE}",
		"precision": "${PRECISION}",
		"model": "${MODEL}"
	}
EOF
)"
	metrics_json_add_array_element "$json"
	metrics_json_end_array "Config"
}

get_pre_trained_model() {
	pushd "${TMP_DIR}"
	wget "${PRE_TRAINED_MODEL}"
	popd
}

get_intelai_models() {
 	go get -d "${INTELAI_REPO}" || true
	pushd "${GOPATH}/src/${INTELAI_REPO}/benchmarks"
	python launch_benchmark.py \
		--in-graph "${TMP_DIR}/${PRE_TRAINED_MODEL_FILE}" \
		--model-name "${MODEL_VERSION}" \
		--framework "${FRAMEWORK}" \
		--precision "${PRECISION}" \
		--mode "${MODE}" \
		--batch-size="${BATCH_SIZE}" \
		--output-dir="${TMP_DIR}" \
		--docker-image "${DOCKER_IMAGE}"
	popd
}

function main() {
	cmds=("docker" "python" "wget")

	init_env
	check_cmds "${cmds[@]}"
	metrics_json_init
	save_config
	get_pre_trained_model
	get_intelai_models
	metrics_json_start_array
	local get_results_file=$(find "${TMP_DIR}" -type f -name "*.log")

	local average=$(cat "${get_results_file}" | grep "Average time" | cut -d ':' -f2 | sed -e 's/^[ \t]*//')
	local throughput=$(cat "${get_results_file}" | grep "Throughput" | cut -d ':' -f2| sed -e 's/^[ \t]*//')
	local json="$(cat << EOF
	{
		"Average Time" : "${average}",
		"Throughput" : "${throughput}"
	}
EOF
)"
	metrics_json_add_array_element "$json"
	metrics_json_end_array "Results"
	metrics_json_save
	docker rm -f $(docker ps -qa)
	clean_env
}

main "$@"
