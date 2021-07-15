#!/bin/bash
#
# Copyright (c) 2021 Red Hat, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#

cidir="$(dirname $0)/../"
source "$cidir/lib.sh"

#
# Variables that the user can overwrite
#
KATA_TESTS_JOB_RUNNER="${KATA_TESTS_JOB_RUNNER:-vm}"

#
# Script variables
#

ALL_AVAILABLE_JOBS=(
	"baremetal-pmem"
	"cri_containerd_k8s"
	"cri_containerd_k8s_initrd"
	"cri_containerd_k8s_complete"
	"cri_containerd_k8s_minimal"
	"crio_k8s"
	"crio_k8s_complete"
	"crio_k8s_minimal"
	"cloud-hypervisor-k8s-crio"
	"cloud-hypervisor-k8s-containerd"
	"cloud-hypervisor-k8s-containerd-minimal"
	"Ccloud-hypervisor-k8s-containerd-fullL"
	"firecracker"
	"vfio"
	"virtiofs_experimental"
	"metrics"
	"metrics_experimental")

usage() {
	cat <<-EOF
	Run a CI job.
	User can select the runner which will trigger the job within a given environment.

	Usage: $0 [-h] [-l] [-j JOB_ID]

	Options:
	       -l: list all defined jobs
	       -j JOB_ID: run the job of JOB_ID

	Environment variables:
	        KATA_TESTS_JOB_RUNNER: switch between 'local' and 'vm' (default) runners"
	EOF
}

list_jobs_id() {
	echo ${ALL_AVAILABLE_JOBS[@]}
}

#
# Note:
#
# Any function named as _do_run_NAME is interpreted as the implementation of
# the NAME runner. So if you want to add new runners then you just need to
# create a function with that name pattern.
#

# Local runner implementation.
_do_run_local() {
	local job_id="$1"
	local runner_script="${cidir}/run.sh"
	local setup_script="${cidir}/setup.sh"
	# Convert the ID to uppercase.
	typeset -u CI_JOB="$job_id"
	# Export it.
	typeset -x CI_JOB
	bash "$setup_script"
	bash "$runner_script"
}

# VM runner implementation.
_do_run_vm() {
	local job_id="$1"
	local runner_script="${cidir}/job/vm/vm_runner.sh"
	# Convert the ID to uppercase.
	typeset -u CI_JOB="$job_id"
        # Export it.
        typeset -x CI_JOB
	bash "$runner_script" -r "$job_id"
}

# Check if the runner $1 exists.
# i.e., if the function _do_run_$1 is defined then it returns 0, otherwise return 1.
_runner_exists() {
	local runner="$1"
        LC_ALL=C type "_do_run_${runner}" &>/dev/null
}

run_job() {
	local job_id="$1"
	local runner="$2"

	[ -n "$job_id" ] || \
		die "It must be provided the job ID."
	echo "${ALL_AVAILABLE_JOBS[@]}" | grep "\<${job_id}\>" &>/dev/null || \
		die "Job '$job_id' not found."

	[ -n "$runner" ] || \
		die "It must be provided a job runner."
	_runner_exists "$runner" || \
		die "Runner '$runner' is not implemented."

	echo "Run job '$job_id' on '$runner' runner."
	"_do_run_${runner}" "$job_id"
}

main() {
	if [ $# -lt 1 ]; then
		usage
		exit 0
	fi
	while getopts hj:l opt; do
		case $opt in
			h) usage; exit 0;;
			l) list_jobs_id;;
			j) run_job "$OPTARG" "${KATA_TESTS_JOB_RUNNER}";;
			*) usage; exit 1;;
		esac
	done
}

main $@
