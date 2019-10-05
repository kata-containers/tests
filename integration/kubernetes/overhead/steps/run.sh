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
csv_file=""
info_test="no-information"

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
		if [ "${cid}" == "null" ]; then
			echo "waiting for container running ..."
			sleep "${wait_time_sec}"
		fi
	done
	echo "kubernetes container ID: ${cid}"
	cid=$(echo "${cid}" | cut -d/ -f3)
	echo "Container ID to get in kata: ${cid}"
	if ! sudo "${RUNTIME}" list | grep "${cid}" >/dev/null; then
		sudo "${RUNTIME}" list
		kubectl describe pod -l app="overhead"
		kubectl logs -l app="overhead"
		exit 1
	fi
	cpu_overhead_sum=0
	memory_overhead_sum=0
	cpu_guest_sum=0
	cpu_host_sum=0
	for i in $(seq 1 ${samples}); do
		overhead_sample=$(sudo "${RUNTIME}" kata-overhead "${cid}")

		cpu_overhead_sample=$(printf "%s" "${overhead_sample}" | grep cpu_overhead | cut -d= -f2)
		cpu_overhead_sum=$(echo "${cpu_overhead_sum} + ${cpu_overhead_sample}" | bc)
		info "sample $i cpu overhead: ${cpu_overhead_sample}"

		memory_overhead_sample=$(printf "%s" "${overhead_sample}" | grep memory_overhead | cut -d= -f2)
		memory_overhead_sum=$(echo "${memory_overhead_sum} + ${memory_overhead_sample}" | bc)
		info "sample $i memory overhead: ${memory_overhead_sample}"

		cpu_guest_sample=$(printf "%s" "${overhead_sample}" | grep "cpu_guest=" | cut -d= -f2)
		cpu_guest_sum=$(echo "${cpu_guest_sum} + ${cpu_guest_sample}" | bc)
		info "sample $i cpu_guest: ${cpu_guest_sample}"

		cpu_host_sample=$(printf "%s" "${overhead_sample}" | grep "cpu_host=" | cut -d= -f2)
		cpu_host_sum=$(echo "${cpu_host_sum} + ${cpu_host_sample}" | bc)
		info "sample $i cpu_host: ${cpu_host_sample}"
	done

	# TODO: should we take the max ovehead value or the max cpu usage from guest sample
	cpu_overhead=$(echo "${cpu_overhead_sum} / ${samples}" | bc)
	memory_overhead=$(echo "${memory_overhead_sum} / ${samples}" | bc)
	cpu_host=$(echo "${cpu_host_sum} / ${samples}" | bc)
	cpu_guest=$(echo "${cpu_guest_sum} / ${samples}" | bc)
	vm_cpus=$(printf "%s" "${overhead_sample}" | grep "vm_cpus=" | cut -d= -f2)

	if [ -n "${csv_file}" ]; then
		if [ ! -f "${csv_file}" ]; then
			echo "workload,cpu_host_usage,cpu_guest_usage,cpu_overhead,memory_overhead,vm_cpus" >"${csv_file}"
		fi
		echo "${info_test},${cpu_host},${cpu_guest},${cpu_overhead},${memory_overhead},${vm_cpus}" >>"${csv_file}"
	fi
}

usage() {
	cat <<EOT
Usage:
${script_name} [options] app-label

app-label: name of the label to use to get pod overhead
--samples <n>: number of samples to collect, default ${samples}
--csv <file> : save data on csv
--info       : used to for csv to identify test with other tests

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
		"--csv")
			csv_file="${2}"
			shift 2
			;;
		"--info")
			info_test="${2}"
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
