#!/usr/bin/env bash
#
# Copyright (c) 2020 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

# Generate Jenkins metrics report from job data and local results.


set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

script_name=${0##*/}
script_dir=$(dirname "$(readlink -f "$0")")

# Base dir of where we store the downloaded data.
datadir="${script_dir}/data"

help() {
	usage=$(cat << EOF
Usage: ${script_name} [-h] [options] <jenkins-job-name>
   Description:
	Gather statistics from recent Jenkins CI metrics builds and generate a report.

   Options:
	-h,          Print this help
EOF
)
echo "$usage"
}

main() {
	local OPTIND
	while getopts "h" opt;do
		case ${opt} in
			h)
				help
				exit 0;
				;;
			?)
				# parse failure
				help
				echo "Failed to parse arguments" >&2
				exit 1
				;;
		esac
	done
	shift $((OPTIND-1))

	repo=${1:-}
	if [ "${repo}" == ""  ]; then
		help && exit 1
	fi

	# Where metrics tools generate data results
	results_dir="${script_dir}/../../../metrics/results"
	# Where metrics tools generate the report
	report_dir="${script_dir}/../../../metrics/report"
	# Where job results should be stored
	# Use basename of job report
	# the report tools look for data subdirectory under ${results_dir}
	job_results_dir="${results_dir}/$(basename ${repo})"
	# Where local results should be stored
	local_results_dir="${results_dir}/new"

	# Move local results to a subdir, needed by makereport.sh
	mkdir -p "${local_results_dir}"
	find "${results_dir}" -maxdepth 1 -name '*.json' -exec mv {} "${local_results_dir}" \;

	# Remove any old data from job
	rm -rf "${datadir}"
	rm -rf "${job_results_dir}"

	# Get data from job
	"${script_dir}/history.sh" -r "${repo}" -n 1

	# Find data and move to sub dir in results dir to have two subsets
	mkdir -p "${job_results_dir}"
	find "${datadir}" -name '*.json' -exec mv {} "${job_results_dir}" \;

	cd "${report_dir}"
	./makereport.sh
}

main "$@"
