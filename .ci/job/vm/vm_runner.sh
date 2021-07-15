#!/bin/bash
#
# Copyright (c) 2021 Red Hat
#
# SPDX-License-Identifier: Apache-2.0
#
# Defines the vm_runner interface.

vm_dir=$(dirname "$0")
cidir="${vm_dir}/../../"
source "${cidir}/lib.sh"

# The VM engine. Default to Vagrant.
KATA_TESTS_VM_ENGINE=${KATA_TESTS_VM_ENGINE:-"vagrant"}
# The default VM name.
KATA_TESTS_VM_NAME=${KATA_TESTS_VM_NAME:-"fedora"}

# Some jobs cannot run inside a VM. For instance, those which need bare-metal
# machine. So here it keeps a list of unsupported jobs.
UNSUPPORTED_JOBS=(
	"baremetal-pmem"
)

#KATA_TESTS_VM_NAME= The VM name
#KATA_TESTS_VM_ENV_FILE= File that contain variables to be exported in the VM environment
#KATA_TESTS_VM_ENGINE= The VM engine. Default to Vagrant

# Load a VM engine implementation.
#
# A VM engine should implement the following functions:
#
#  is_engine_available()
#  is_vm_running(name)
#  vm_start(name, force_destroy=true)
#  vm_destroy(name)
#  vm_run_cmd(name)
#  vm_shell()
#  list_vms()
#
# Params:
#  $1 - the engine name.
_load_engine() {
	local name="$1"
	local impl="${vm_dir}/impl_${name}.sh"
	if [ -z "$name" ]; then
		echo "It must be provided a VM engine name."
		echo "The supported engines: $(do_engine_list)"
		die "Bailing out..."
	fi
	if [ -f "$impl" ]; then
		source "${vm_dir}/impl_${name}.sh" &>/dev/null
	else
		echo "The VM engine '${name}' is not implemented."
		echo "The supported engines: $(do_engine_list)"
		die "Bailing out..."
	fi
	is_engine_available || \
		die "The VM engine '${name}' seems not installed or proper configured on the system."
}

usage() {
	cat <<-EOF
	This program implements the VM runner.
	NOTE: End users should not run it.

	Usage: $0 [-c] [-e] [-h] [-l] [-r JOB_ID]

	Options:
	       -c: destroy all active VMs
	       -e: list supported engines
	       -h: print this help message
	       -l: list all supported VMs
	       -r JOB_ID: run the job of JOB_ID

	Environment variables:
	  KATA_TESTS_VM_ENGINE: choose the VM engine. Defaults to 'vagrant'
	  KATA_TESTS_VM_NAME: for actions which require a VM "fedora"
	EOF
}

# Print the list of implemented engines.
#
do_engine_list() {
        echo $(find ${vm_dir} -name "impl_*.sh" | sed -e 's/.*impl_\(.*\).sh/\1/')
}

# Destroy all VMs.
#
do_vm_clean_all() {
	local vm
	echo "Going to destroy all VMs"
	for vm in $(list_vms); do
		echo "Destroy: $vm"
		vm_destroy "$vm" || true
	done
}

# Print the list of VM names.
#
do_vm_list() {
	echo "The avaliable VMs:"
	list_vms
}

# Run the job $1 in the $2 VM.
#
do_run_job() {
	local job_id="$1"
	local vm="$2"
	local cmd
	echo "Run job $job_id on $vm VM"
	# Assume $GOPATH is exported
	cmd='cd ${GOPATH}/src/github.com/kata-containers/tests/.ci'
	cmd+=' && export KATA_TESTS_JOB_RUNNER=local'
	cmd+=" && make job-run-${job_id}"
	echo "Start the VM"
	vm_start "$vm"
	echo "Run the command $cmd"
	vm_run_cmd "$vm" "$cmd"
}

main () {
	local action=""
	_load_engine "${KATA_TESTS_VM_ENGINE}"
	while getopts cehlr: opt; do
		case $opt in
			c) action="vm_clean_all";;
			e) action="engine_list";;
			h) usage; exit 0;;
			l) action="vm_list";;
			r)
				action="run_job"
				job="$OPTARG"
			;;
			*) usage; exit 1;;
		esac
	done
	if [ -z "${action}" ]; then
		usage
		exit 0
	elif [ "${action}" == "run_job" ]; then
		do_run_job "${job}" "${KATA_TESTS_VM_NAME}"
	else
		do_${action}
	fi
}

main $@
