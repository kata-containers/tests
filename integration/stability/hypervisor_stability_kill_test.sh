#!/bin/bash
#
# Copyright (c) 2019-2021 HyperHQ Inc, Intel Corporation.
#
# SPDX-License-Identifier: Apache-2.0
#
# This test will kill a running container's
# hypervisor, and see how we react to cleanup.

set -e

cidir=$(dirname "$0")

source "${cidir}/../../metrics/lib/common.bash"

# Environment variables
IMAGE="${IMAGE:-quay.io/prometheus/busybox:latest}"
CONTAINER_NAME="${CONTAINER_NAME:-test}"
PAYLOAD_ARGS="${PAYLOAD_ARGS:-tail -f /dev/null}"
# The based pidof command-line. This should have appended the ID of processes
# which should be ignored, so use this variable instead of plain `pidof`.
pidof_cmd="pidof"

setup()  {
	restart_containerd_service
	extract_kata_env
	HYPERVISOR_NAME=$(basename ${HYPERVISOR_PATH})
	sudo ctr image pull $IMAGE
	[ $? != 0 ] && die "Unable to get image $IMAGE"

	# Build the base pidof command-line so that PID of running hypervisors
	# are omitted.
	for omit_pid in $(pidof ${HYPERVISOR_NAME}); do
		pidof_cmd+=" -o $omit_pid"
	done
	sudo ctr run --runtime=$CTR_RUNTIME -d $IMAGE $CONTAINER_NAME sh -c $PAYLOAD_ARGS
	num=$(${pidof_cmd} ${HYPERVISOR_NAME} | wc -w)
	[ ${num} -eq 1 ] || die "hypervisor count:${num} expected:1"
}

kill_hypervisor()  {
	pid=$(${pidof_cmd} ${HYPERVISOR_NAME})
	[ -n ${pid} ] || die "failed to find hypervisor pid"
	sudo kill -KILL ${pid} || die "failed to kill hypervisor (pid ${pid})"
	# signal is async and we've seen failures hypervisor not being killed immediately.
	sleep 1
	num=$(${pidof_cmd} ${HYPERVISOR_NAME} | wc -w)
	[ ${num} -eq 0 ] || die "hypervisor count:${num} expected:0"
	sudo ctr tasks rm -f $(sudo ctr task list -q)
	sudo ctr c rm $(sudo ctr c list -q)
	[ $? -eq 0 ] || die "failed to force removing container $CONTAINER_NAME"
}

teardown()  {
	echo "Ending hypervisor stability test"
	clean_env_ctr
}

trap teardown EXIT

echo "Starting hypervisor stability test"
setup

echo "Running hypervisor stability test"
kill_hypervisor
