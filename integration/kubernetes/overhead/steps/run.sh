#!/bin/bash
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
readonly script_name="$(basename "${BASH_SOURCE[0]}")"
samples=50
wait_time_sec=5
max_tries=10
label_to_check="overhead"
RUNTIME=${RUNTIME:-kata-runtime}

die() {
	echo "ERROR:$*" 1>&2
	exit 1
}
info() {
	echo "INFO: $*" 1>&2
}

get_overhead() {
	local app_label=${1:-}
	[ -n "${app_label}" ] || die "no app"
	cid="null"
	try=0
	while [ "$cid" == "null" ]; do
		if ((try >= max_tries)); then
			die "could not get container ID, max_tries=${max_tries} reached"
		fi
		cid=$(kubectl get pods -l app="${app_label}" -o json | jq -r .items[0].status.containerStatuses[0].containerID)
		if [ -n "${cid}" ]; then
			echo "waiting for container running ..."
			sleep "${wait_time_sec}"
		fi
	done
	echo "kubernetes container ID: ${cid}"
	cid=$(echo "${cid}" | cut -d/ -f3)
	echo "Container ID to get in kata: ${cid}"
	if ! sudo "${RUNTIME}" list | grep "${cid}"; then
		sudo "${RUNTIME}" list
		exit 1
	fi
	overhead_sum=0
	for i in $(seq 1 ${samples}); do
		overhead_sample=$(sudo "${RUNTIME}" kata-overhead "${cid}" | grep cpu_overhead | cut -d= -f2)
		overhead_sum=$(echo "${overhead_sum} + ${overhead_sample}" | bc)
		info "sample $i :${overhead_sample}"
	done

	echo "${overhead_sum} / ${samples}" | bc
}

usage() {
	cat <<EOT
Usage:
${script_name} [options] app-label

--samples: number of samples to collect, default ${samples}
app-label: name of the label to use to get pod overhead

example:

${script_name} --samples 5 nginx
EOT
}

main() {
	shopt -s extglob
	while (("$#")); do
		case "${1:-}" in
		"-h" | "--help")
			usage
			exit 0
			;;
		"--samples")
			samples="${2}"
			shift 2
			;;
		-*)
			die "Invalid option: ${1:-}"
			shift
			;;
		*) # preserve positional arguments
			#PARAMS="$PARAMS $1"
			break
			;;
		esac
	done

	local app_label=${1:-${label_to_check}}
	if [ -z "${app_label}" ]; then
		usage
		exit 1
	fi
	get_overhead "${app_label}"
}
main $*
