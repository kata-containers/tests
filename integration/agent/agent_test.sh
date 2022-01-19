#!/bin/bash
#
# Copyright (c) 2022 Ant Group
#
# SPDX-License-Identifier: Apache-2.0
#
# This will run a containers and then check
# whether the kata-agent threads namespaces
# were changed during create container processes.

set -e
set -o errexit
set -o nounset
set -o pipefail

[ -n "$BASH_VERSION" ] && set -o errtrace
[ -n "${DEBUG:-}" ] && set -o xtrace

dir_path=$(dirname "$0")
source "${dir_path}/../../lib/common.bash"
source "${dir_path}/../../metrics/lib/common.bash"

CTR_RUNTIME="${CTR_RUNTIME:-io.containerd.kata.v2}"
CONTAINER_NAME="${CONTAINER_NAME:-test}"
IMAGE="${IMAGE:-quay.io/library/busybox:latest}"

setup() {
        restart_containerd_service
        check_processes
}

test_agent() {
	sudo ctr image pull "${IMAGE}"
        [ $? != 0 ] && die "Unable to get image $IMAGE"
        sudo ctr run --runtime="${CTR_RUNTIME}" -d --privileged --rm --mount type=bind,src=/proc,dst=/proc,options=rbind:ro "${IMAGE}" "${CONTAINER_NAME}" sh -c "tail -f /dev/null" || die "Test failed"

	sudo ctr t exec --exec-id test ${CONTAINER_NAME} sh -c 'ps -ef | grep kata-agent | grep -v grep'

	agent_pid=$(sudo ctr t exec --exec-id test ${CONTAINER_NAME} sh -c 'ps -ef | grep kata-agent | grep -v grep' | awk '{print $1}')
	agent_tasks=$(sudo ctr t exec --exec-id test ${CONTAINER_NAME} sh -c "ls /proc/$agent_pid/task")

	ns="cgroup ipc mnt net pid user uts"

	for t in $agent_tasks; do
		for i in $ns; do 
			agent_namespace=$(sudo ctr t exec --exec-id test ${CONTAINER_NAME} sh -c "ls -al /proc/$t/ns/$i" | awk '{print $NF}')
			root_namespace=$(sudo ctr t exec --exec-id test ${CONTAINER_NAME} sh -c "ls -al /proc/1/ns/$i" | awk '{print $NF}')

    			[ "$agent_namespace" == "$root_namespace" ] || die "the agent's namespace $agent_namespace isn't equal to $root_namespace"
		done
	done	
}

teardown() {
        clean_env_ctr
        check_processes
}

trap teardown EXIT

echo "Running setup"
setup

echo "Running stability integration tests with agent"
test_agent
