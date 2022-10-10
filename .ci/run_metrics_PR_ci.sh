#!/bin/bash
# Copyright (c) 2017-2022 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

# Note - no 'set -e' in this file - if one of the metrics tests fails
# then we wish to continue to try the rest.
# Finally at the end, in some situations, we explicitly exit with a
# failure code if necessary.

declare -r SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
declare -r RESULTS_DIR=${SCRIPT_DIR}/../metrics/results
declare -r CHECKMETRICS_DIR=${SCRIPT_DIR}/../cmd/checkmetrics

# Where to look by default, if this machine is not a static CI machine with a fixed name.
declare -r CHECKMETRICS_CONFIG_DEFDIR="/etc/checkmetrics"

# Where to look if this machine is a static CI machine with a known fixed name.
declare -r CHECKMETRICS_CONFIG_DIR="${CHECKMETRICS_DIR}/ci_worker"
declare -r CM_DEFAULT_DENSITY_CONFIG="${CHECKMETRICS_DIR}/baseline/density-CI.toml"

# Test labels
declare -r TEST_BOOT="boot"
declare -r TEST_DENSITY="density"
declare -r TEST_NETWORK="network"
declare -r TEST_BLOGBENCH="blogbench"

# Some tests can only run in cloud hypervisor
declare -r CLH_NAME="cloud-hypervisor"

source "${SCRIPT_DIR}/../metrics/lib/common.bash"

KATA_HYPERVISOR="${KATA_HYPERVISOR:-qemu}"

# Density paramter to set the number of iterations of the test
DENSITY_FORMAT_RESULTS="${DENSITY_FORMAT_RESULTS:-json}"

# Density parameters to select between 'csv' and 'json' results format
DENSITY_TEST_REPETITIONS="${DENSITY_TEST_REPETITIONS:-1}"

# metrics selector among: density, boot, blogbench, all
TEST_SELECTOR="${TEST_SELECTOR:-all}"

# Set up the initial state
init() {
	metrics_onetime_init
}

# Execute metrics scripts
run() {
	if [ "${TEST_SELECTOR}" != "all" ] && [ "${TEST_SELECTOR}" != "${TEST_DENSITY}" ]  && \
	[ "${TEST_SELECTOR}" != "${TEST_BLOGBENCH}" ] && [ "${TEST_SELECTOR}" != "${TEST_BOOT}" ] && \
	[ "${TEST_SELECTOR}" != "${TEST_NETWORK}" ]; then
		info "Invalid test: $TEST_SELECTOR"
		return 1
	fi

	pushd "$SCRIPT_DIR/../metrics"

	# Cloud hypervisor tests are being affected by kata-containers/kata-containers/issues/1488
	if [ "${KATA_HYPERVISOR}" != "cloud-hypervisor" ] && [[ -f ${KSM_ENABLE_FILE} ]]; then
		# If KSM is available on this platform, let's run any tests that are
		# affected by having KSM on/orr first, and then turn it off for the
		# rest of the tests, as KSM may introduce some extra noise in the
		# results by stealing CPU time for instance.
		if [ "${TEST_SELECTOR}" = "all" ] || [ "${TEST_SELECTOR}" = "density" ]; then

			save_ksm_settings
			trap restore_ksm_settings EXIT QUIT KILL
			set_ksm_aggressive

			# Run the memory footprint test - the main test that
			# KSM affects.
			bash density/memory_usage.sh 20 300 auto
		fi
	fi

	restart_docker_service
	disable_ksm

	# Run the density tests - no KSM, so no need to wait for settle
	# (so set a token 5s wait)
	if [ "${TEST_SELECTOR}" = "all" ] || [ "${TEST_SELECTOR}" = "${TEST_DENSITY}" ]; then
		bash density/memory_usage.sh 20 5
	fi

	# Run storage tests
	if [ "${TEST_SELECTOR}" = "all" ] || [ "${TEST_SELECTOR}" = "${TEST_BLOGBENCH}" ]; then
		bash storage/blogbench.sh
	fi
	# Run the density test inside the container
	if [ "${TEST_SELECTOR}" = "all" ] || [ "${TEST_SELECTOR}" = "${TEST_DENSITY}" ]; then
		bash density/memory_usage_inside_container.sh ${DENSITY_FORMAT_RESULTS} ${DENSITY_TEST_REPETITIONS}
	fi

	# Run the time tests
	if [ "${TEST_SELECTOR}" = "all" ] || [ "${TEST_SELECTOR}" = "${TEST_BOOT}" ]; then
		bash time/launch_times.sh -i public.ecr.aws/ubuntu/ubuntu:latest -n 20
	fi

	# run network tests
	if [ "${TEST_SELECTOR}" = "all" ] || [ "${TEST_SELECTOR}" = "${TEST_NETWORK}" ]; then
		if [ "${KATA_HYPERVISOR}" = "${CLH_NAME}" ]; then
			start_kubernetes
			bash network/latency_kubernetes/latency-network.sh
			bash network/iperf3_kubernetes/k8s-network-metrics-iperf3.sh -a
			bash storage/fio-k8s/fio-test-ci.sh
			end_kubernetes
			check_processes
		else
			info "${TEST_NETWORK} can't run using ${KATA_HYPERVISOR}"
		fi
	fi

	popd
}

# Check the results
check() {
	[ ! -n "${METRICS_CI}" ] && return 0

	if [ "${TEST_SELECTOR}" = "all" ]; then

		# Ensure we have the latest checkemtrics
		pushd "$CHECKMETRICS_DIR"
		make
		sudo make install
		popd

		# For bare metal repeatable machines, the config file name is tied
		# to the uname of the machine.
		local CM_BASE_FILE="${CHECKMETRICS_CONFIG_DIR}/checkmetrics-json-${KATA_HYPERVISOR}-$(uname -n).toml"

		checkmetrics --debug --percentage --basefile ${CM_BASE_FILE} --metricsdir ${RESULTS_DIR}
		cm_result=$?
		if [ ${cm_result} != 0 ]; then
			info "run-metrics-ci: checkmetrics FAILED (${cm_result})"
			exit ${cm_result}
		fi
	fi

	# Save results
	local DEST_DIR="${RESULTS_DIR}/artifacts"
	sudo mkdir -p "${DEST_DIR}"

	info "Moving results to $DEST_DIR"
	for f in ${RESULTS_DIR}/*.json; do
		mv -- "$f" "${DEST_DIR}/${KATA_HYPERVISOR}-$(basename $f)"
	done
}

info "run-metrics-ci"
init
run
check
