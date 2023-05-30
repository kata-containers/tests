#!/bin/bash
#
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#
# This script runs the Sonobuoy e2e Conformance tests.
# Run this script once your K8s cluster is running.
# WARNING: it is prefered to use containerd as the
# runtime interface instead of cri-o as we have seen
# errors with cri-o that still need to be debugged.

set -o errexit
set -o nounset
set -o pipefail

DEBUG=${DEBUG:-}
[ -n "$DEBUG" ] && set -o xtrace

export KUBECONFIG=$HOME/.kube/config
SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_PATH}/../../../lib/common.bash"
source "${SCRIPT_PATH}/../../../.ci/lib.sh"

CI=${CI:-false}
RUNTIME="${RUNTIME:-containerd-shim-kata-v2}"
CRI_RUNTIME="${CRI_RUNTIME:-containerd}"
MINIMAL_K8S_E2E="${MINIMAL_K8S_E2E:-false}"
KATA_HYPERVISOR="${KATA_HYPERVISOR:-}"

# Overall Sonobuoy timeout in minutes.
WAIT_TIME=${WAIT_TIME:-180}

JOBS_FILE="${SCRIPT_PATH}/e2e_k8s_jobs.yaml"

create_kata_webhook() {
	pushd "${SCRIPT_PATH}/../../../kata-webhook" >>/dev/null
	# Create certificates for the kata webhook
	./create-certs.sh

	# Apply kata-webhook deployment
	kubectl apply -f deploy/

	# Ensure the kata-webhook is working
	./webhook-check.sh
	popd
}

delete_kata_webhook() {
	pushd "${SCRIPT_PATH}/../../../kata-webhook" >>/dev/null

	# Apply kata-webhook deployment
	kubectl delete -f deploy/

	popd
}

get_sonobuoy() {
	sonobuoy_repo=$(get_test_version "externals.sonobuoy.url")
	version=$(get_test_version "externals.sonobuoy.version")
	arch="$(${SCRIPT_PATH}/../../../.ci/kata-arch.sh --golang)"
	sonobuoy_tar="sonobuoy_${version}_linux_${arch}.tar.gz"
	install_path="/usr/bin"

	curl -LO "${sonobuoy_repo}/releases/download/v${version}/${sonobuoy_tar}"
	sudo tar -xzf "${sonobuoy_tar}" -C "$install_path"
	sudo chmod +x "${install_path}/sonobuoy"
	rm -f "${sonobuoy_tar}"
}

# Input:
# - yaml list key
# - yaml file
# Output
# - string: | separated values of the list
yaml_list_to_str_regex() {
	local list="${1}"
	local yaml_file=${2:-"|"}
	local query=".${list}"
	query+=' | join("|")?'
	"${GOPATH}/bin/yq" -j read "${yaml_file}" | jq -r "${query}"
}

run_sonobuoy() {
	# Run Sonobuoy e2e tests
	info "Starting sonobuoy execution."
	info "When using kata as k8s runtime, the tests take around 2 hours to finish."

	local skipped_tests_file="${SCRIPT_PATH}/skipped_tests_e2e.yaml"
	local skipped_tests=$("${GOPATH}/bin/yq" read "${skipped_tests_file}" "${CRI_RUNTIME}")

	# Default skipped tests for Conformance testing:
	skip_options="Alpha|\[(Disruptive|Feature:[^\]]+|Flaky)\]"
	local skip_list
	skip_list=$(yaml_list_to_str_regex "\"${CRI_RUNTIME}\"" "${skipped_tests_file}")
	if [ "${skip_list}" != "" ]; then
		skip_options+="|${skip_list}"
	fi

	skip_list=$(yaml_list_to_str_regex "hypervisor.\"${KATA_HYPERVISOR}\"" "${skipped_tests_file}")
	if [ "${skip_list}" != "" ]; then
		skip_options+="|${skip_list}"
	fi

	local cmd="sonobuoy"
	cmd+=" run"
	cmd+=" --wait=${WAIT_TIME}"

	if [ "${MINIMAL_K8S_E2E}" == "true" ]; then
		minimal_focus=$(yaml_list_to_str_regex "jobs.minimal.focus" "${JOBS_FILE}")
		# Not required to skip as only what is defined in toml should be executed.
		if [ "${minimal_focus}" != "" ]; then
			cmd+=" --e2e-focus=\"${minimal_focus}\""
		else
			# For MINIMAL_K8S_E2E focus list should not be empty
			die "minimal focus query returned empty list"
		fi
	else
		if [ "${skip_options}" != "" ]; then
			cmd+=" --e2e-skip=\"${skip_options}\""
		fi
	fi
	echo "running: ${cmd}"
	eval "${cmd}"

	e2e_result_dir="$(mktemp -d /tmp/kata_e2e_results.XXXXX)"
	{
		sonobuoy status --json
		if ! results=$(sonobuoy retrieve "${e2e_result_dir}"); then
			die "failed to retrieve results"
		fi

		sonobuoy results "${results}" --mode=dump

		pushd "${e2e_result_dir}"
		tar -xvf "${results}"
		e2e_result_log=$(find "${e2e_result_dir}/plugins/e2e" -name "e2e.log")
		info "Results of the e2e tests can be found on: $e2e_result_log"
		popd

		failed_query='.plugins | .[] | select( ."result-status" | contains("failed"))'
		failed=$(sonobuoy status --json | jq "${failed_query}")
		if [ "${failed}" != "" ]; then
			if [ "$CI" == true ]; then
				cat "$e2e_result_log"
			fi
			sonobuoy status --json | jq "${failed_query}"
			die "Found failed tests in end-to-end k8s test"
		fi
		local expected_passed_query="jobs.${CI_JOB:-}.passed"
		local expected_passed=$("${GOPATH}/bin/yq" read "${JOBS_FILE}" "${expected_passed_query}")
		if [ "${expected_passed}" != "" ]; then
			passed_query='.plugins | [ .[]."result-counts".passed] | add'
			passed=$(sonobuoy status --json | jq "${passed_query}")
			if [ "${expected_passed}" != "${passed}" ]; then
				die "expected ${expected_passed} tests to pass, but ${passed} passed"
			else
				info "All ${passed} tests passed as expected"
			fi
		else
			info "Not found ${expected_passed_query} for job ${CI_JOB:-} in ${JOBS_FILE}"
		fi
	} | tee "${e2e_result_dir}/summary"
}

cleanup() {
	if [ -d "${e2e_result_dir:-}" ]; then
		info "Results directory "${e2e_result_dir}" will not be deleted"
		log_file="${e2e_result_dir}/plugins/e2e/results/global/e2e.log"
		if [ -f "${log_file}" ]; then
			info "View results"
			cat ${log_file}
		else
			warn "Tests results file ${log_file} not found"
		fi
	fi
	{
		if command -v sonobuoy &>/dev/null; then
			info "View sonobuoy status"
			sonobuoy status
			# Remove sonobuoy execution pods
			sonobuoy delete
		fi
	} || true

	if [ "$RUNTIME" == "containerd-shim-kata-v2" ]; then
		delete_kata_webhook
	fi

	# Revert the changes applied by the integration/kubernetes/init.sh
	# script when it was called in our setup.sh.
	info "Clean up the environment"
	bash -c "$(readlink -f ${SCRIPT_PATH}/../cleanup_env.sh)" || true
}

trap "{ cleanup; }" EXIT

main() {
	if [ "$RUNTIME" == "containerd-shim-kata-v2" ]; then
		create_kata_webhook
	fi

	get_sonobuoy
	run_sonobuoy
}

main
