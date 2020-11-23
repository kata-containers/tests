#!/usr/bin/env bash
#
# Copyright (c) 2018-2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

# This file contains common functions that
# are being used by our metrics and integration tests

# Place where virtcontainers keeps its active pod info
VC_POD_DIR="${VC_POD_DIR:-/run/vc/sbs}"

# Sandbox runtime directory
RUN_SBS_DIR="${RUN_SBS_DIR:-/run/vc/sbs}"

# Kata tests directory used for storing various test-related artifacts.
KATA_TESTS_BASEDIR="${KATA_TESTS_LOGDIR:-/var/log/kata-tests}"

# Directory that can be used for storing test logs.
KATA_TESTS_LOGDIR="${KATA_TESTS_LOGDIR:-${KATA_TESTS_BASEDIR}/logs}"

# Directory that can be used for storing test data.
KATA_TESTS_DATADIR="${KATA_TESTS_DATADIR:-${KATA_TESTS_BASEDIR}/data}"

# Directory that can be used for storing cache kata components
KATA_TESTS_CACHEDIR="${KATA_TESTS_CACHEDIR:-${KATA_TESTS_BASEDIR}/cache}"

KATA_HYPERVISOR="${KATA_HYPERVISOR:-qemu}"
experimental_qemu="${experimental_qemu:-false}"

die() {
	local msg="$*"
	echo "ERROR: $msg" >&2
	exit 1
}

warn() {
	local msg="$*"
	echo "WARNING: $msg"
}

info() {
	local msg="$*"
	echo "INFO: $msg"
}

handle_error() {
	local exit_code="${?}"
	local line_number="${1:-}"
	echo "Failed at $line_number: ${BASH_COMMAND}"
	exit "${exit_code}"
}
trap 'handle_error $LINENO' ERR

# Check if the $1 argument is the name of a 'known'
# Kata runtime. Of course, the end user can choose any name they
# want in reality, but this function knows the names of the default
# and recommended Kata docker runtime install names.
is_a_kata_runtime(){
	case "$1" in
	"kata-runtime") ;&	# fallthrough
	"kata-qemu") ;&		# fallthrough
	"kata-fc")
		echo "1"
		return
		;;
	esac

	echo "0"
}


# Try to find the real runtime path for the docker runtime passed in $1
get_docker_kata_path(){
	local jpaths=$(sudo docker info --format "{{json .Runtimes}}" || true)
	local rpath=$(jq .\"$1\".path <<< "$jpaths")
	# Now we have to de-quote it..
	rpath="${rpath%\"}"
	rpath="${rpath#\"}"
	echo "$rpath"
}

# Gets versions and paths of all the components
# list in kata-env
extract_kata_env(){
	RUNTIME_CONFIG_PATH=$(kata-runtime kata-env --json | jq -r .Runtime.Config.Path)
	RUNTIME_VERSION=$(kata-runtime kata-env --json | jq -r .Runtime.Version | grep Semver | cut -d'"' -f4)
	RUNTIME_COMMIT=$(kata-runtime kata-env --json | jq -r .Runtime.Version | grep Commit | cut -d'"' -f4)
	RUNTIME_PATH=$(kata-runtime kata-env --json | jq -r .Runtime.Path)

	# Shimv2 path is being affected by https://github.com/kata-containers/kata-containers/issues/1151
	SHIM_PATH=$(whereis containerd-shim-kata-v2 | cut -d":" -f2)
	SHIM_VERSION=$(${SHIM_PATH} --version)

	HYPERVISOR_PATH=$(kata-runtime kata-env --json | jq -r .Hypervisor.Path)
	HYPERVISOR_VERSION=$(${HYPERVISOR_PATH} --version | head -n1)
	VIRTIOFSD_PATH=$(kata-runtime kata-env --json | jq -r .Hypervisor.VirtioFSDaemon)

	INITRD_PATH=$(kata-runtime kata-env --json | jq -r .Initrd.Path)
	NETMON_PATH=$(kata-runtime kata-env --json | jq -r .Netmon.Path)
}

# Checks that processes are not running
check_processes() {
	extract_kata_env

	# Only check the kata-env if we have managed to find the kata executable...
	if [ -x "$RUNTIME_PATH" ]; then
		local vsock_configured=$($RUNTIME_PATH kata-env | awk '/UseVSock/ {print $3}')
		local vsock_supported=$($RUNTIME_PATH kata-env | awk '/SupportVSock/ {print $3}')
	else
		local vsock_configured="false"
		local vsock_supported="false"
	fi

	general_processes=( ${HYPERVISOR_PATH} ${SHIM_PATH} )

	for i in "${general_processes[@]}"; do
		if pgrep -f "$i"; then
			die "Found unexpected ${i} present"
		fi
	done
}

# Checks that pods were not left in a directory
check_pods_in_dir() {
    local DIR=$1
    if [ -d ${DIR} ]; then
		# Verify that pods were not left
		pods_number=$(ls ${DIR} | wc -l)
		if [ ${pods_number} -ne 0 ]; then
            ls ${DIR}
			die "${pods_number} pods left and found at ${DIR}"
		fi
	else
		echo "Not ${DIR} directory found"
	fi
}

# Checks that pods were not left
check_pods() {
	check_pods_in_dir ${VC_POD_DIR}
}

# Check that runtimes are not running, they should be transient
check_runtimes() {
	runtime_number=$(ps --no-header -C ${RUNTIME} | wc -l)
	if [ ${runtime_number} -ne 0 ]; then
		die "Unexpected runtime ${RUNTIME} running"
	fi
}

# Clean environment, this function will try to remove all
# stopped/running containers.
clean_env()
{
	# If the timeout has not been set, default it to 30s
	# Docker has a built in 10s default timeout, so make ours
	# longer than that.
	KATA_DOCKER_TIMEOUT=${KATA_DOCKER_TIMEOUT:-30}
	containers_running=$(sudo timeout ${KATA_DOCKER_TIMEOUT} docker ps -q)

	if [ ! -z "$containers_running" ]; then
		# First stop all containers that are running
		# Use kill, as the containers are generally benign, and most
		# of the time our 'stop' request ends up doing a `kill` anyway
		sudo timeout ${KATA_DOCKER_TIMEOUT} docker kill $containers_running

		# Remove all containers
		sudo timeout ${KATA_DOCKER_TIMEOUT} docker rm -f $(docker ps -qa)
	fi
}

get_pod_config_dir() {
	pod_config_dir="${BATS_TEST_DIRNAME}/runtimeclass_workloads"
	info "k8s configured to use runtimeclass"
}
