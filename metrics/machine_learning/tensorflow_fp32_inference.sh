#!/bin/bash
#
# Copyright (c) 2020 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

# Description of the test:
# This test runs the 'tensorflow benchmark'
# inside a container for the fp32 inference model
# https://github.com/IntelAI/models/blob/master/benchmarks/image_recognition/tensorflow/resnet50v1_5/
set -e

# General env
SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_PATH}/../lib/common.bash"

TEST_NAME="tensorflow_fp32_inference_container"
IMAGE="tensorflow_fp32_inference"
DOCKERFILE="${SCRIPT_PATH}/Dockerfile_fp32_inference/Dockerfile"
CI_JOB="${CI_JOB:-""}"
MODEL="resnet50"
MODEL_VERSION="${MODEL}v1_5"
PRE_TRAINED_MODEL_FILE="${MODEL}_v1.pb"
FRAMEWORK="tensorflow"
BATCH_SIZE="10"
PRECISION="fp32"
MODE="inference"
http_proxy="${http_proxy:-}"
https_proxy="${https_proxy:-}"
TEST_DIRECTORY="tensorflow"
BENCHMARK_DIRECTORY="/${TEST_DIRECTORY}/intel_models/benchmarks"
RESULTS_DIR=$(mktemp --tmpdir -d results.XXXXXXXXXX)
TMP_FILE="/tmp/results"
CMD_GET_FILE="find ${TMP_FILE} -type f -name '*.log'"
CMD="mkdir ${TMP_FILE} && python3 ${BENCHMARK_DIRECTORY}/launch_benchmark.py --in-graph /${TEST_DIRECTORY}/${PRE_TRAINED_MODEL_FILE} \
--model-name ${MODEL_VERSION} --framework ${FRAMEWORK} --precision ${PRECISION} --mode ${MODE} --batch-size ${BATCH_SIZE} \
--output-dir=${TMP_FILE} --benchmark-only && sleep 10"
launch_timeout="10"
log_timeout="10"
file_timeout="200"

remove_tmp_dir() {
	rm -rf "${RESULTS_DIR}"
}

trap remove_tmp_dir EXIT

save_config(){
	metrics_json_start_array

	local json="$(cat << EOF
	{
		"image": "${IMAGE}",
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

function main() {
	cmds=("docker")

	init_env
	check_cmds "${cmds[@]}"
	check_dockerfiles_images "${IMAGE}" "${DOCKERFILE}"
	metrics_json_init
	save_config
	docker run -tid --env http_proxy="${http_proxy}" --env https_proxy="${https_proxy}" --runtime="${RUNTIME}" "${IMAGE}" sh -c "${CMD}"
	CONTAINERS_ID=$(docker ps -a --format "table {{.ID}}" | tail -n +2)

	# Verify that container is running
	echo "Verify that container is running"
	for i in $(seq "${launch_timeout}") ; do
		containers_launched=$(docker ps -a | grep "${IMAGE}" | grep "Up" | wc -l)
		if [ "${containers_launched}" -eq 1 ]; then
			echo "Container is running"
			break
		fi
		sleep 1
		[ "${i}" == "${launch_timeout}" ] && return 1
	done

	# Verify that inside the tensorflow container the results log file has been created
	echo "Check that results log file is being created"
	for i in $(seq "${log_timeout}") ; do
		file_existance="ls ${TMP_FILE} | wc -l"
		check_file=$(docker exec "${CONTAINERS_ID}" sh -c "${file_existance}")
		# We need a number of retries as the results log is not created inmediately
		# when the tensorflow benchmark is being launched
		number_retries="10"
		for i in $(seq 0 "${number_retries}"); do
			if [ "${check_file}" -eq 1 ]; then
				get_file_name=$(docker exec "${CONTAINERS_ID}" sh -c "${CMD_GET_FILE}")
				break
			else
				sleep 1
			fi
		done
		if [ ! -z "${check_file}" ]; then
			echo "Tensorflow log has been created"
			break
		fi
		sleep 1
		[ "${i}" == "${log_timeout}" ] && return 1
	done

	# We need to verify that the tensorflow benchmark results are completed as the log is created
	# but is being populated while the benchmark is running, this will ensure that we get the
	# complete log
	for i in $(seq "${file_timeout}") ; do
		check_results=$(docker exec "${CONTAINERS_ID}" sh -c "cat ${get_file_name}")
		echo "${check_results}" > LOG
		verify_results_generation=$(echo "${check_results}" | grep "Throughput" | wc -l)
		if [ "${verify_results_generation}" -eq 1 ]; then
 			echo "Results were generated"
			break
		fi
		sleep 1
		[ "${i}" == "${file_timeout}" ] && return 1
	done

	docker cp "${CONTAINERS_ID}:${get_file_name}" "${RESULTS_DIR}"
	pushd "${RESULTS_DIR}"
	log_name=$(echo "${get_file_name}" | cut -d '/' -f4)
	cat "${log_name}" >> "results"
	popd

	metrics_json_start_array

	local output=$(cat "$RESULTS_DIR/results")
	local average=$(echo "${output}" | grep "Average time" | cut -d ':' -f2 | sed -e 's/^[ \t]*//')
	local throughput=$(echo "${output}" | grep "Throughput" | cut -d ':' -f2| sed -e 's/^[ \t]*//')
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
