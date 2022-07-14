#!/bin/bash
#
# Copyright (c) 2018-2020 Intel Corporation
# Copyright (c) 2021 Red Hat, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
# This script should be sourced so that the environment gets exported variables
# used to control the setup and execution of tests.
#
# Export the CI_JOB environment variable if you need job-specific variables
# set apart from the defaults.
#

CI_JOB=${CI_JOB:-}

# List of all setup flags used by scripts
init_ci_flags() {
	# Make jobs work like in CI
	# CI disables non-working tests
	export CI="true"

	# Many checks assume this environment variable to be not set
	# (e.g. [ -n $KATA_DEV_MODE ]). As a result, even its value is
	# set to 'false', the check would think we are in "kata_dev_mode".
	# export KATA_DEV_MODE="false"

	# Install crio
	export CRIO="no"
	# Install cri-containerd
	export CRI_CONTAINERD="no"
	# Default cri runtime - used to setup k8s
	export CRI_RUNTIME=""
	# Ask runtime to only use cgroup at pod level
	# Useful for pod overhead
	export DEFSANDBOXCGROUPONLY="false"
	# Build Kata for Confidential Containers
	# Values: "yes|no"
	export KATA_BUILD_CC="no"
	# Hypervisor to use
	export KATA_HYPERVISOR=""
	# Install k8s
	export KUBERNETES="no"
	# Run a subset of k8s e2e test
	# Will run quick to ensure e2e setup is OK
	# - Use false for PRs
	# - Use true for nightly testing
	export MINIMAL_K8S_E2E="false"
	# Test cgroup v2
	export TEST_CGROUPSV2="false"
	# Run crio functional test
	export TEST_CRIO="false"
	# Use experimental qemu
	# Values: true|false
	export experimental_qemu="false"
	# Run the kata-check checks
	export RUN_KATA_CHECK="true"
	# Use devmapper snapshotter
	# Only works with containerd
	export USE_DEVMAPPER="false"

	# METRICS_CI flags
	# Request to run METRICS_CI
	# Values: "true|false"
	export METRICS_CI="false"
	# Metrics check values depend in the env it run
	# Define a profile to check on PRs
	# Values: empty|string : String will be used to find a profile with defined values to check
	export METRICS_CI_PROFILE=""
	# Check values for a profile defined as CLOUD
	# Deprecated use METRICS_CI_PROFILE will be replaced by METRICS_CI_PROFILE=cloud-metrics
	export METRICS_CI_CLOUD=""
	# Generate a report using a jenkins job data
	# Name of the job to get data from
	export METRICS_JOB_BASELINE=""
	# Configure test to use Kata SHIM V2
	export SHIMV2_TEST="true"
	export CTR_RUNTIME="io.containerd.kata.v2"
}

# Setup Kata Containers Environment
#
# - If the repo is "tests", this will call the script living in that repo
#   directly.
# - If the repo is not "tests", call the repo-specific script (which is
#   expected to call the script of the same name in the "tests" repo).
case "${CI_JOB}" in
"BAREMETAL-PMEM"|"PMEM")
	init_ci_flags
	export CRI_CONTAINERD="yes"
	export CRI_RUNTIME="containerd"
	export KATA_HYPERVISOR="qemu"
	export KUBERNETES="yes"
	;;
"BAREMETAL-QAT"|"QAT")
	init_ci_flags
	export CRI_CONTAINERD="yes"
	export CRI_RUNTIME="containerd"
	export KATA_HYPERVISOR="qemu"
	;;
"CRI_CONTAINERD"|"CRI_CONTAINERD_K8S"|"CC_CRI_CONTAINERD")
	# This job only tests containerd + k8s
	init_ci_flags
	export CRI_CONTAINERD="yes"
	export CRI_RUNTIME="containerd"
	export KATA_HYPERVISOR="qemu"
	case "${CI_JOB}" in
		"CRI_CONTAINERD_K8S")
			export KUBERNETES="yes"
			;;
		"CC_CRI_CONTAINERD")
			# Export any CC specific environment variables
			export KATA_BUILD_CC="yes"
			;;
	esac
	;;
"CRI_CONTAINERD_K8S_DEVMAPPER")
	init_ci_flags
	export CRI_CONTAINERD="yes"
	export CRI_RUNTIME="containerd"
	export KATA_HYPERVISOR="qemu"
	export KUBERNETES="yes"
	export USE_DEVMAPPER="true"
	;;
"CC_CRI_CONTAINERD_CLOUD_HYPERVISOR")
	# This job only tests containerd + k8s
	init_ci_flags
	export CRI_CONTAINERD="yes"
	export CRI_RUNTIME="containerd"
	export KATA_HYPERVISOR="cloud-hypervisor"
	# Export any CC specific environment variables
	export KATA_BUILD_CC="yes"
	;;
"CRIO_K8S")
	init_ci_flags
	export CRI_RUNTIME="crio"
	export CRIO="yes"
	export KATA_HYPERVISOR="qemu"
	export KUBERNETES="yes"
	# test images in cri-o repo are mostly x86_64 specific, so ignore cri-o intergration tests on aarch64, etc.
	if [ "$arch" == "x86_64" ]; then
		export TEST_CRIO="true"
	fi
	;;
"CRIO_K8S_COMPLETE")
	init_ci_flags
	export CRI_RUNTIME="crio"
	export CRIO="yes"
	export KUBERNETES="yes"
	;;
"CRIO_K8S_MINIMAL")
	init_ci_flags
	export CRI_RUNTIME="crio"
	export CRIO="yes"
	export KUBERNETES="yes"
	export MINIMAL_K8S_E2E="true"
	;;
"CLOUD-HYPERVISOR-K8S-CRIO")
	init_ci_flags
	export CRI_RUNTIME="crio"
	export CRIO="yes"
	export KATA_HYPERVISOR="cloud-hypervisor"
	export KUBERNETES="yes"
	;;
"CLOUD-HYPERVISOR-K8S-CONTAINERD")
	init_ci_flags
	export CRI_CONTAINERD="yes"
	export CRI_RUNTIME="containerd"
	export KATA_HYPERVISOR="cloud-hypervisor"
	export KUBERNETES="yes"
	;;
"CLOUD-HYPERVISOR-K8S-CONTAINERD-DEVMAPPER")
	init_ci_flags
	export CRI_CONTAINERD="yes"
	export CRI_RUNTIME="containerd"
	export KATA_HYPERVISOR="cloud-hypervisor"
	export KUBERNETES="yes"
	export USE_DEVMAPPER="true"
	;;
"EXTERNAL_CLOUD_HYPERVISOR")
	init_ci_flags
	export CRI_CONTAINERD="yes"
	export CRI_RUNTIME="containerd"
	export KATA_HYPERVISOR="cloud-hypervisor"
	export KUBERNETES="no"
	;;
"EXTERNAL_CRIO")
	init_ci_flags
	export CRIO="yes"
	export CRI_RUNTIME="crio"
	export KATA_HYPERVISOR="qemu"
	export KUBERNETES="yes"
	export TEST_CRIO="true"
	export MINIMAL_K8S_E2E="true"
	export MINIMAL_CONTAINERD_K8S_E2E="true"
	;;
"FIRECRACKER")
	init_ci_flags
	export CRI_CONTAINERD="yes"
	export CRI_RUNTIME="containerd"
	export KATA_HYPERVISOR="firecracker"
	export KUBERNETES="yes"
	export USE_DEVMAPPER="true"
	;;
"VFIO")
	init_ci_flags
	export CRI_CONTAINERD="yes"
	export CRI_RUNTIME="containerd"
	export KATA_HYPERVISOR="qemu"
	;;
"VIRTIOFS_EXPERIMENTAL")
	init_ci_flags
	export CRI_CONTAINERD="yes"
	export CRI_RUNTIME="containerd"
	export DEFVIRTIOFSCACHESIZE="1024"
	export KUBERNETES="yes"
	export experimental_qemu="true"
	;;
"METRICS")
	init_ci_flags
	export CRI_CONTAINERD="yes"
	export CRI_RUNTIME="containerd"
	export KATA_HYPERVISOR="qemu"
	export KUBERNETES="yes"
	export METRICS_CI=1
;;
esac
