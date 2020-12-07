#!/bin/bash
#
# Copyright (c) 2020 Red Hat, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
set -e

GOPATH=${GOPATH:-$(go env GOPATH)}
script_dir="$(realpath $(dirname $0))"
source "$script_dir/../../../lib/common.bash"
tests_dir="$script_dir/../../../"
source "$script_dir/../lib.sh"

cmd="openshift-tests"
readonly test_cases_file="${script_dir}/test_cases.txt"
readonly default_kata_runtimeclass="$kata_runtimeclass"

# Whether to run openshift-tests on dry-run mode or not.
dry_run="false"
# Whether to configure the OpenShift cluster or not.
configure_cluster="false"

function usage() {
	cat << EOF
This script runs a sub-set of the OpenShift e2e tests in other to test Kata
Containers in a running OpenShift cluster.

It assumes that the KUBECONFIG variable is exported and that it points to a
cluster where Kata Containers is already installed.

The cluster also should have:
 1) The $default_kata_runtimeclass runtimeClass resource;
 2) A running admission controller which annotates any created Pod
    to use that runtimeClass.

If you choose to have the cluster configured by this script, beware that it
will not return to its original state on the end.

Usage $0: [-c] [-d] [-r NAME] -o DIRECTORY, where:
  -c           Configure the cluster to run the tests.
  -d           Run the tests in dry-run mode.
  -h           Print this message.
  -o           Directory to store the output files.
  -r           The runtimeClass name (default is '$default_kata_runtimeclass').
               This option should not be used with -c.
EOF
}

function setup()
{
	mkdir -p $output_dir

	# If the cluster is already configured by the user then only check that the
	# admission controller is active.
	#
	if [ "$configure_cluster" == "true" ]; then
		[ "$default_kata_runtimeclass" == "$kata_runtimeclass" ] || \
			# To configure the cluster it should use the default runtimeClass name, and
			# overwriting the runtimeClass won't work. So options -r and -c should not
			# be used together.
			die "To configure the cluster you should not overwrite the default runtimeClass name"
		configure_cluster || die "Failed to configure the cluster"
	else
		info "Check the kata admission controller is active"
		is_kata_admission_controller_active || \
			die "Admission controller not active"
	fi

	# Build the openshift tests binary if not available on PATH.
	if ! command -v "$cmd" >/dev/null; then
		info "'$cmd' command not found on PATH. Build it from source"
		cmd="$(build_openshift_tests)" || die "The build failed"
	fi

}

function do_test()
{
        cmd+=" run"
        # Save the tests results in junit format.
        #
        cmd+=" --junit-dir ${output_dir}"
        # In case dry run mode is on.
        #
        if [ $dry_run == "true" ]; then
                cmd+=" --dry-run"
        fi

        cmd+=" -f -"
        info "Run the OpenShift tests"
        # The test cases file may have commented lines which should be ignored.
        cat $test_cases_file | grep -v "^#" | ${cmd}
}

function main()
{
	while getopts "cdho:r:" opt; do
		case ${opt} in
			c) configure_cluster="true" ;;
			d) dry_run="true" ;;
			h) usage; exit 0 ;;
			o) output_dir=${OPTARG} ;;
			r) kata_runtimeclass=${OPTARG} ;;
			*)
				usage
				exit 1
				;;
		esac
	done

	[ -n "$KUBECONFIG" ] || \
		die "The KUBECONFIG variable is unset. Use -h for help."
	[ -n "$output_dir" ] || \
		die "The output directory is unset. Use -o DIRECTORY or -h for help."

	setup
	do_test || die "TESTS FAILED"
	info "TESTS PASSED"
}

main "$@"
