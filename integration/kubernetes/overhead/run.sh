#!/bin/bash
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

readonly script_dir=$(dirname $(readlink -f "$0"))
readonly script_name="$(basename "${BASH_SOURCE[0]}")"
label_to_check="overhead"
pre_run_check_file="./check_before_get_overhead.sh"
samples=${SAMPLES:-5}

usage() {
	cat <<EOT
Usage:
${script_name} [options] <dir>

<dir>: directory that has a workload.yaml

       The workload.yaml should provide a pod with a label 'app'
       The pod with a app label will be sampled to get its overhead
       The the pod label must be the same name as "${label_to_check}"

--samples: number of samples to collect, default ${samples}

example:

${script_name} fio
EOT
}

finish() {
	"${script_dir}/steps/cleanup.sh"
}

main() {
	local test=${1:-}
	if [ -z "${test}" ]; then
		usage
		exit 1
	fi
	while (("$#")); do
		case "${1:-}" in
		"-h" | "--help")
			usage
			exit 0
			;;
		"-s" | "--samples")
			samples="${1}"
			shift
			;;
		-*)
			die "Invalid option: -${1:-}" "1"
			shift
			;;
		*) # preserve positional arguments
			#PARAMS="$PARAMS $1"
			break
			;;
		esac
	done

	csv_file="${PWD}/ovehead.csv"
	cd "${test}"
	trap finish EXIT
	"${script_dir}/steps/setup.sh"

	if [ -x "${pre_run_check_file}" ]; then
		echo "found ${pre_run_check_file}, running..."
		"${pre_run_check_file}"
	fi

	"${script_dir}/steps/run.sh" --samples "${samples}" --csv "${csv_file}" --info "${test}"
}

main $*
