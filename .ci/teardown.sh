#!/bin/bash
#
# Copyright (c) 2017-2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

cidir=$(dirname "$0")
source "${cidir}/lib.sh"

collect_logs()
{
	local -r log_copy_dest="$1"

	local -r containerd_shim_kata_v2_log_filename="containerd-shim-kata-v2.log"
	local -r containerd_shim_kata_v2_log_path="${log_copy_dest}/${containerd_shim_kata_v2_log_filename}"
	local -r containerd_shim_kata_v2_log_prefix="containerd-shim-kata-v2_"

	local -r kata_runtime_log_filename="kata-runtime.log"
	local -r kata_runtime_log_path="${log_copy_dest}/${kata_runtime_log_filename}"
	local -r kata_runtime_log_prefix="kata-runtime_"

	local -r ksm_throttler_log_filename="kata-ksm_throttler.log"
	local -r ksm_throttler_log_path="${log_copy_dest}/${ksm_throttler_log_filename}"
	local -r ksm_throttler_log_prefix="kata-ksm_throttler_"

	local -r vc_throttler_log_filename="kata-vc_throttler.log"
	local -r vc_throttler_log_path="${log_copy_dest}/${vc_throttler_log_filename}"
	local -r vc_throttler_log_prefix="kata-vc_throttler_"

	local -r containerd_log_filename="containerd.log"
	local -r containerd_log_path="${log_copy_dest}/${containerd_log_filename}"
	local -r containerd_log_prefix="containerd_"

	local -r crio_log_filename="crio.log"
	local -r crio_log_path="${log_copy_dest}/${crio_log_filename}"
	local -r crio_log_prefix="crio_"

	local -r docker_log_filename="docker.log"
	local -r docker_log_path="${log_copy_dest}/${docker_log_filename}"
	local -r docker_log_prefix="docker_"

	local -r collect_data_filename="kata-collect-data.log"
	local -r collect_data_log_path="${log_copy_dest}/${collect_data_filename}"
	local -r collect_data_log_prefix="kata-collect-data_"

	local -r kubelet_log_filename="kubelet.log"
	local -r kubelet_log_path="${log_copy_dest}/${kubelet_log_filename}"
	local -r kubelet_log_prefix="kubelet_"

	local -r kernel_log_filename="kernel.log"
	local -r kernel_log_path="${log_copy_dest}/${kernel_log_filename}"
	local -r kernel_log_prefix="kernel_"

	local -r tracing_log_filename="kata-runtime-traces.json"
	local -r tracing_log_path="${log_copy_dest}/${tracing_log_filename}"
	local -r tracing_log_prefix="tracing_"

	local -r virtiofs_log_filename="virtiofs.log"
	local -r virtiofs_log_path="${log_copy_dest}/${virtiofs_log_filename}"
	local -r virtiofs_log_prefix="virtiofs_"

	local -r collect_script="kata-collect-data.sh"

	# If available, procenv will be run twice - once as the current user
	# and once as the superuser.
	local -r procenv_user_log_filename="procenv-${USER}.log"
	local -r procenv_user_log_path="${log_copy_dest}/${procenv_user_log_filename}"
	local -r procenv_root_log_filename="procenv-root.log"
	local -r procenv_root_log_path="${log_copy_dest}/${procenv_root_log_filename}"

	have_collect_script="no"
	collect_script_path="$(command -v $collect_script)" && have_collect_script="yes"

	have_procenv="no"
	[ -n "$(command -v procenv)" ] && have_procenv="yes"

	# Copy log files if a destination path is provided, otherwise simply
	# display them.
	if [ "${log_copy_dest}" ]; then
		# Create directory if it doesn't exist
		[ -d "${log_copy_dest}" ] || mkdir -p "${log_copy_dest}"

		# Create the log files
		sudo journalctl --no-pager -t kata > "${containerd_shim_kata_v2_log_path}"
		sudo journalctl --no-pager -t kata-runtime > "${kata_runtime_log_path}"
		sudo journalctl --no-pager -u kata-ksm-throttler > "${ksm_throttler_log_path}"
		sudo journalctl --no-pager -u kata-vc-throttler > "${vc_throttler_log_path}"

		sudo journalctl --no-pager -u containerd > "${containerd_log_path}"
		sudo journalctl --no-pager -u crio > "${crio_log_path}"
		sudo journalctl --no-pager -u docker > "${docker_log_path}"
		sudo journalctl --no-pager -u kubelet > "${kubelet_log_path}"
		sudo journalctl --no-pager -t kernel > "${kernel_log_path}"
		sudo journalctl --no-pager -t virtiofsd > "${virtiofs_log_path}"

		[ "${have_collect_script}" = "yes" ] && sudo -E PATH="$PATH" "${collect_script_path}" > "${collect_data_log_path}"

		tracing_log_directory="/var/log/kata-tests/logs/traces"

		if [ -f "${tracing_log_directory}/${tracing_log_filename}" ]; then
			cp "${tracing_log_directory}/${tracing_log_filename}" "${tracing_log_path}"
		fi

		# Split them in 50 MiB subfiles to avoid too large files.
		local -r subfile_size=52428800

		pushd "${log_copy_dest}"
		split -b "${subfile_size}" -d "${containerd_shim_kata_v2_log_path}" "${containerd_shim_kata_v2_log_prefix}"
		split -b "${subfile_size}" -d "${kata_runtime_log_path}" "${kata_runtime_log_prefix}"
		split -b "${subfile_size}" -d "${ksm_throttler_log_path}" "${ksm_throttler_log_prefix}"
		split -b "${subfile_size}" -d "${vc_throttler_log_path}" "${vc_throttler_log_prefix}"
		split -b "${subfile_size}" -d "${containerd_log_path}" "${containerd_log_prefix}"
		split -b "${subfile_size}" -d "${crio_log_path}" "${crio_log_prefix}"
		split -b "${subfile_size}" -d "${docker_log_path}" "${docker_log_prefix}"
		split -b "${subfile_size}" -d "${kubelet_log_path}" "${kubelet_log_prefix}"
		split -b "${subfile_size}" -d "${kernel_log_path}" "${kernel_log_prefix}"
		if [ -f "${tracing_log_directory}/${tracing_log_filename}" ]; then
			split -b "${subfile_size}" -d "${tracing_log_path}" "${tracing_log_prefix}"
		fi
		split -b "${subfile_size}" -d "${virtiofs_log_path}" "${virtiofs_log_prefix}"

		[ "${have_collect_script}" = "yes" ] &&  split -b "${subfile_size}" -d "${collect_data_log_path}" "${collect_data_log_prefix}"

		local prefixes=""
		prefixes+=" ${containerd_shim_kata_v2_log_prefix}"
		prefixes+=" ${kata_runtime_log_prefix}"
		prefixes+=" ${containerd_log_prefix}"
		prefixes+=" ${crio_log_prefix}"
		prefixes+=" ${docker_log_prefix}"
		prefixes+=" ${kubelet_log_prefix}"
		prefixes+=" ${ksm_throttler_log_prefix}"
		prefixes+=" ${vc_throttler_log_prefix}"
		prefixes+=" ${kernel_log_prefix}"
		prefixes+=" ${virtiofs_log_prefix}"

		[ "${have_collect_script}" = "yes" ] && prefixes+=" ${collect_data_log_prefix}"

		if [ "${have_procenv}" = "yes" ]
		then
			procenv --file "${procenv_user_log_path}"
			sudo -E procenv --file "${procenv_root_log_path}" && \
				sudo chown ${USER}: "${procenv_root_log_path}"
		fi

		local prefix

		# Compress log files
		for prefix in $prefixes
		do
			gzip -9 "$prefix"*
		done

		# The procenv logs are tiny so don't require chunking
		gzip -9 "${procenv_user_log_path}" "${procenv_root_log_path}"

		# Remove *.log files, which contain the uncompressed data.
		rm -f *".log"

		popd
	else
		echo "containerd-shim-kata-v2 Log:"
		sudo journalctl --no-pager -t kata

		echo "Kata Containers Runtime Log:"
		sudo journalctl --no-pager -t kata-runtime

		echo "Kata Containers KSM Throttler Log:"
		sudo journalctl --no-pager -u kata-ksm-throttler

		echo "Kata Containers Virtcontainers Throttler Log:"
		sudo journalctl --no-pager -u kata-vc-throttler

		echo "Containerd Log:"
		sudo journalctl --no-pager -u containerd

		echo "CRI-O Log:"
		sudo journalctl --no-pager -u crio

		echo "Docker Log:"
		sudo journalctl --no-pager -u docker

		echo "Kubelet Log:"
		sudo journalctl --no-pager -u kubelet

		echo "Kernel Log:"
		sudo journalctl --no-pager -t kernel

		if [ -f "${tracing_log_directory}/${tracing_log_filename}" ]; then
			echo "Runtime Tracing Log:"
			cat "${tracing_log_directory}/${tracing_log_filename}"
		fi

		echo "Virtiofs Log:"
		sudo journalctl --no-pager -t virtiofs

		if [ "${have_collect_script}" = "yes" ]
		then
			echo "Kata Collect Data script output"
			sudo -E PATH="$PATH" $collect_script
		fi

		if [ "${have_procenv}" = "yes" ]
		then
			echo "Procenv output (user $USER):"
			procenv

			echo "Procenv output (superuser):"
			sudo -E procenv
		fi
	fi
}

check_log_files()
{
	info "Checking log files"

	make log-parser

	local component
	local unit
	local file
	local args
	local cmd

	for component in \
		kata \
		kata-runtime

	do
		file="${component}.log"
		args="--no-pager -q -o cat -a -t \"${component}\""

		cmd="sudo journalctl ${args} > ${file}"
		eval "$cmd" || true
	done

	for unit in \
		kata-ksm-throttler \
		kata-vc-throttler
	do
		file="${unit}.log"
		args="--no-pager -q -o cat -a -u \"${unit}\""

		cmd="sudo journalctl ${args} |grep ^time= > ${file}"
		eval "$cmd" || true
	done

	local -r logs=$(ls "$(pwd)"/*.log || true)
	local ret

	cmd="kata-log-parser"
	args="--debug --check-only --error-if-no-records"

	{ $cmd $args $logs; ret=$?; } || true

	local errors=0
	local log

	for log in $logs
	do
		local pattern
		local results

		# Display *all* errors caused by runtime exceptions and fatal
		# signals.
		for pattern in "fatal error" "fatal signal" "segfault at [0-9]"
		do
			# Search for pattern and print all subsequent lines with specified log
			# level.
			results=$(grep "${pattern}" "$log" || true )
			if [ -n "$results" ]
			then
				errors=1
				echo >&2 -e "ERROR: detected ${pattern} in '${log}'\n${results}"
			fi
		done
	done

	# Always remove logs since:
	#
	# - We don't want to waste disk-space.
	# - collect_logs() will save the full logs anyway.
	# - the log parser tool shows full details of what went wrong.
	rm -f $logs

	[ "$errors" -ne 0 ] && exit 1

	[ $ret -eq 0 ] && true || false
}

check_collect_script()
{
	local -r cmd="kata-collect-data.sh"
	local -r cmdpath=$(command -v "$cmd" || true)

	local msg="Kata data collection script"

	[ -z "$cmdpath" ] && info "$msg not found" && return

	info "Checking $msg"

	sudo -E PATH="$PATH" $cmd
}

main()
{
	# We always want to try to collect the logs at the end of a test run,
	# so don't run with "set -e".
	collect_logs "$@"

	# The following tests can fail and should fail the teardown phase
	# (but only after we've collected the logs).
	set -e

	check_log_files
	check_collect_script
}

main "$@"
