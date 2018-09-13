#!/bin/bash
#
# Copyright (c) 2018 HyperHQ Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
# A temporary test script to verify docker connect with kata-netmon

set -e -x

cidir=$(dirname "$0")

source "${cidir}/../../metrics/lib/common.bash"

# Environment variables
IMAGE="${IMAGE:-busybox}"
CONTAINER_NAME=$(random_name)
PAYLOAD_ARGS="${PAYLOAD_ARGS:-tail -f /dev/null}"

runtime_config_path=${RUNTIME_CONFIG_PATH}

kata_runtime_bin=$(command -v kata-runtime)

docker_network_name="foobartestnetwork"

setup() {
	clean_env
}

enable_netmon() {
	echo "enable netmon in ${runtime_config_path}"
	sudo sed -i -e 's/^#\(enable_netmon =\).*$/\1 true/g' "${runtime_config_path}"
	grep -A 10 netmon ${runtime_config_path}
}

disable_netmon() {
	echo "disable netmon"
	sudo sed -i -e 's/^\(enable_netmon =\).*$/#\1 true/g' "${runtime_config_path}"
}

test_docker_connect() {
	echo "test docker create connect"
	sudo docker network create $docker_network_name
	sudo docker run --runtime=$RUNTIME -d --name $CONTAINER_NAME $IMAGE $PAYLOAD_ARGS
	sudo docker network connect $docker_network_name $CONTAINER_NAME
	# sleep a lot to let network connect take efffect even in nested environment
	sleep 10
	sudo docker exec $CONTAINER_NAME ip addr
	ipaddr=$(sudo docker exec $CONTAINER_NAME ip addr show eth1 | sed -ne 's/.*inet \([.0-9]\{7,15\}\)\/[0-9]\{1,2\} .*/\1/p')
	sudo docker rm -f $CONTAINER_NAME
	sudo docker network rm $docker_network_name
	echo hotplugged network ip address is $ipaddr
	test -n "$ipaddr"
}

teardown() {
	clean_env
}

echo "Starting docker connect test"
setup

echo "Running docker connect test"
enable_netmon
test_docker_connect
disable_netmon

echo "Ending docker connect test"
teardown
