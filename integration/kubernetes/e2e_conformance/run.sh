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

export KUBECONFIG=$HOME/.kube/config
SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_PATH}/../../../lib/common.bash"
source "${SCRIPT_PATH}/../../../.ci/lib.sh"

CI=${CI:-false}
RUNTIME="${RUNTIME:-kata-runtime}"
CRI_RUNTIME="${CRI_RUNTIME:-crio}"
MINIMAL_K8S_E2E="${MINIMAL_K8S_E2E:-true}"
KATA_HYPERVISOR="${KATA_HYPERVISOR:-}"

# Overall Sonobuoy timeout in minutes.
WAIT_TIME=${WAIT_TIME:-180}

create_kata_webhook() {
	pushd "${SCRIPT_PATH}/../../../kata-webhook" >> /dev/null
	# Create certificates for the kata webhook
	./create-certs.sh

	# Apply kata-webhook deployment
	kubectl apply -f deploy/
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

run_sonobuoy() {
	# Run Sonobuoy e2e tests
	info "Starting sonobuoy execution."
	info "When using kata as k8s runtime, the tests take around 2 hours to finish."

	local skipped_tests_file="${SCRIPT_PATH}/skipped_tests_e2e.yaml"
	local skipped_tests=$("${GOPATH}/bin/yq" read "${skipped_tests_file}" "${CRI_RUNTIME}")
	local skipped_tests_hypervisor=$("${GOPATH}/bin/yq" read "${skipped_tests_file}" "hypervisor.${KATA_HYPERVISOR}")

	# Default skipped tests for Conformance testing:
	_skip_options=("Alpha|\[(Disruptive|Feature:[^\]]+|Flaky)\]|")
	mapfile -t _skipped_tests <<< "${skipped_tests}"
	for entry in "${_skipped_tests[@]}"
	do
		_skip_options+=("${entry#- }|")
	done

	mapfile -t _skipped_tests <<< "${skipped_tests_hypervisor}"
	for entry in "${_skipped_tests[@]}"
	do
		_skip_options+=("${entry#- }|")
	done

	skip_options=$(IFS= ; echo "${_skip_options[*]}")
	skip_options="${skip_options%|}"


	if [ "${MINIMAL_K8S_E2E}" == "true" ]; then
		FOCUS_TEST+="Secrets should be consumable via the environment"
		FOCUS_TEST+="|ConfigMap should be consumable from pods in volume"
		FOCUS_TEST+="|Projected secret should be consumable in multiple volumes"
		FOCUS_TEST+="|Kubelet when scheduling a busybox command in a pod should printk"
		FOCUS_TEST+="|InitContainer \[NodeConformance\] should invoke init containers"
		sonobuoy run --e2e-focus="${FOCUS_TEST}" --e2e-skip="$skip_options" --wait="$WAIT_TIME"
	else
		sonobuoy run --e2e-skip="$skip_options" --wait="$WAIT_TIME"
	fi

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
			sonobuoy status --json | jq {failed_query}
			die "Found failed tests in end-to-end k8s test"
		fi
		local jobs_file="${SCRIPT_PATH}/e2e_k8s_jobs.yaml"
		local expected_passed_query="jobs.${CI_JOB:-}.passed"
		local expected_passed=$("${GOPATH}/bin/yq" read "${jobs_file}" "${expected_passed_query}")
		if [ "${expected_passed}" != "" ];then
			passed_query='.plugins | [ .[]."result-counts".passed] | add'
			passed=$(sonobuoy status --json | jq "${passed_query}")
			if [ "${expected_passed}" != "${passed}" ];then
				die "expected ${expected_passed} tests to pass, but ${passed} passed"
			else
				info "All ${passed} tests passed as expected"
			fi
		else
			info "Not found ${expected_passed_query} for job ${CI_JOB:-} in ${jobs_file}"
		fi
	} |  tee "${e2e_result_dir}/summary"
}

cleanup() {
	info "Results directory "${e2e_result_dir}" will not be deleted"
	# Remove sonobuoy execution pods
	sonobuoy delete
}

trap "{ cleanup; }" EXIT

main() {
	if [ "$RUNTIME" == "kata-runtime" ]; then
		create_kata_webhook
	fi

	get_sonobuoy
	run_sonobuoy
}

main
