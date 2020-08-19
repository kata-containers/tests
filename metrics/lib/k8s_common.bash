#!/bin/bash
#
# Copyright (c) 2020 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

THIS_FILE=$(readlink -f ${BASH_SOURCE[0]})
LIB_DIR=${THIS_FILE%/*}
source ${LIB_DIR}/../../lib/common.bash
source ${LIB_DIR}/json.bash
source /etc/os-release || source /usr/lib/os-release

# Set variables to reasonable defaults if unset or empty
RUNTIME="${RUNTIME:-containerd-shim-kata-v2}"
cri_runtime="${CRI_RUNTIME:-containerd}"

# This function checks existence of commands.
# They can be received standalone or as an array, e.g.
#
# cmds=("cmd1" "cmd2")
# check_cmds "${cmds[@]}"
check_cmds()
{
	local cmd req_cmds=( "$@" )
	for cmd in "${req_cmds[@]}"; do
		if ! command -v "$cmd" > /dev/null 2>&1; then
			die "command $cmd not available"
		fi
		echo "command: $cmd: yes"
	done
}

# This function performs a pull on the image names
# passed in (notionally as 'about to be used'), to ensure
#  - that we have the most upto date images
#  - that any pull/refresh time (for a first pull) does not
#    happen during the test itself.
#
# The image list can be received standalone or as an array, e.g.
#
# images=(“img1” “img2”)
# check_imgs "${images[@]}"
check_images()
{
	local img req_images=( "$@" )
	for img in "${req_images[@]}"; do
		echo "pulling images: $img"
		if ! ctr image pull "$img"; then
			die "Failed to ctr image pull $img"
		fi
		echo "ctr pull'd: $img"
	done
}

# A one time (per uber test cycle) init that tries to get the
# system to a 'known state' as much as possible
metrics_onetime_init()
{
	# The onetime init must be called once, and only once
	if [ ! -z "$onetime_init_done" ]; then
		die "onetime_init() called more than once"
	fi

	# Restart services
	sudo systemctl restart "${cri_runtime}"

	# We want this to be seen in sub shells as well...
	# otherwise init_env() cannot check us
	export onetime_init_done=1
}

# Print a banner to the logs noting clearly which test
# we are about to run
test_banner()
{
	echo -e "\n===== starting test [$1] ====="
}

# Initialization/verification environment. This function makes
# minimal steps for metrics/tests execution.
init_env()
{
	test_banner "${TEST_NAME}"

	cmd=("kubectl")

	# check dependencies
	check_cmds "${cmd[@]}"

	# Remove all stopped containers
	clean_env

	# This clean up is more aggressive, this is in order to
	# decrease the factors that could affect the metrics results.
	kill_processes_before_start
}

# Generate a random name - generally used when creating containers, but can
# be used for any other appropriate purpose
random_name() {
	mktemp -u kata-XXXXXX
}

# Dump diagnostics about our current system state.
# Very useful for diagnosing if we have failed a sanity check
show_system_state() {
	echo "Showing system state:"
	echo " --Kubectl get pods--"
	kubectl get pods --all-namespaces

	local processes="containerd-shim-kata-v2 $(basename ${HYPERVISOR_PATH} | cut -d '-' -f1)"

	for p in ${processes}; do
		echo " --pgrep ${p}--"
		pgrep -a ${p}
	done
}

common_init(){

	# If we are running a kata runtime, go extract its environment
	# for later use.
	local iskata=$(is_a_kata_runtime "$RUNTIME")

	if [ "$iskata" == "1" ]; then
		extract_kata_env
	else
		# We know we have nothing to do for runc
		if [ "$RUNTIME" != "runc" ]; then
			warn "Unrecognised runtime ${RUNTIME}"
		fi
	fi
}

common_init
