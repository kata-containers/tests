#!/bin/bash
#
# Copyright (c) 2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -e

source /etc/os-release || source /usr/lib/os-release
kubernetes_dir=$(dirname "$(readlink -f "$0")")
cidir="${kubernetes_dir}/../../.ci/"
source "${cidir}/lib.sh"

arch="$(uname -m)"

KATA_HYPERVISOR="${KATA_HYPERVISOR:-qemu}"
K8S_TEST_DEBUG="${K8S_TEST_DEBUG:-false}"

K8S_TEST_UNION=("k8s-empty-dirs.bats" \
	"k8s-empty-dirs.bats" \
	"k8s-empty-dirs.bats" \
	"k8s-empty-dirs.bats" \
	"k8s-empty-dirs.bats" \
	"k8s-empty-dirs.bats" \
	"k8s-empty-dirs.bats" \
	"k8s-empty-dirs.bats" \
	"k8s-empty-dirs.bats" \
	"k8s-empty-dirs.bats" \
	"k8s-empty-dirs.bats" \
	"k8s-empty-dirs.bats" \
	"k8s-empty-dirs.bats" \
	"k8s-empty-dirs.bats" \
	"k8s-empty-dirs.bats" \
	"k8s-empty-dirs.bats" \
	"k8s-empty-dirs.bats" \
	"k8s-empty-dirs.bats" \
	"k8s-empty-dirs.bats" \
	"k8s-empty-dirs.bats" \
	"k8s-empty-dirs.bats" \
	"k8s-empty-dirs.bats" \
)

cleanup() {
	if [ ${K8S_TEST_DEBUG} == "true" ]; then
		info "Running on debug mode so skip the cleanup routine"
		info "You can access kubernetes with:\n\tkubectl <command>"
		info "Run the cleanup routine when you are done debugging:\n\t${kubernetes_dir}/cleanup_env.sh"
		return
	fi

	info "Run the cleanup routine"
	${kubernetes_dir}/cleanup_env.sh
}

# Using trap to ensure the cleanup occurs when the script exists.
trap_on_exit() {
	trap 'cleanup' EXIT
}

# we may need to skip a few test cases when running on non-x86_64 arch
if [ -f "${cidir}/${arch}/configuration_${arch}.yaml" ]; then
	config_file="${cidir}/${arch}/configuration_${arch}.yaml"
	arch_k8s_test_union=$(${cidir}/filter/filter_k8s_test.sh ${config_file} "${K8S_TEST_UNION[*]}")
	mapfile -d " " -t K8S_TEST_UNION <<< "${arch_k8s_test_union}"
fi

pushd "$kubernetes_dir"
info "Initialize the test environment"
wait_init_retry="30"
if ! bash ./init.sh; then
	info "Environment initialization failed. Clean up and try again."
	if ! bash ./cleanup_env.sh; then
		die "Failed on cleanup, it won't retry. Bailing out..."
	else
		# trap on exit should be added only if cleanup_env.sh returned
		# success otherwise it will run twice (thus, fail twice).
		trap_on_exit
	fi
	info "Wait ${wait_init_retry} seconds before retry"
	sleep "${wait_init_retry}"
	info "Retry to initialize the test environment..."
	bash ./init.sh
fi
trap_on_exit

info "Run tests"
for K8S_TEST_ENTRY in ${K8S_TEST_UNION[@]}
do
	bats "${K8S_TEST_ENTRY}"
done
popd
