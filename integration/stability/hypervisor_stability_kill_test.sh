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

setup()  {
	sudo systemctl restart containerd
	extract_kata_env
	num=$(pidof ${HYPERVISOR_NAME} | wc -w)
	[ ${num} -eq 0 ] || kill_hypervisor

	sudo ctr image pull $IMAGE
	[ $? != 0 ] && die "Unable to get image $IMAGE"

	HYPERVISOR_NAME=$(basename ${HYPERVISOR_PATH})
	CONTAINERD_RUNTIME="io.containerd.kata.v2"
	sudo ctr run --runtime=$CONTAINERD_RUNTIME -d $IMAGE $CONTAINER_NAME sh -c $PAYLOAD_ARGS
	num=$(pidof ${HYPERVISOR_NAME} | wc -w)
	[ ${num} -eq 1 ] || die "hypervisor count:${num} expected:1"
}

kill_hypervisor()  {
	pid=$(pidof ${HYPERVISOR_NAME})
	[ -n ${pid} ] || die "failed to find hypervisor pid"
	sudo kill -KILL ${pid} || die "failed to kill hypervisor (pid ${pid})"
	# signal is async and we've seen failures hypervisor not being killed immediately.
	sleep 5
	num=$(pidof ${HYPERVISOR_NAME} | wc -w)
	[ ${num} -eq 0 ] || die "hypervisor count:${num} expected:0"
	clean_env_ctr
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
