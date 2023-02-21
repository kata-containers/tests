#!/bin/bash
#
# Copyright (c) 2023 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

set -o pipefail

# General env
SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_PATH}/../metrics/lib/common.bash"

IMAGE="docker.io/library/cassandra:latest"
CONTAINER_NAME="${CONTAINER_NAME:-cassandra_test}"
DOCKER_IMAGE="cassandra:latest"
PAYLOAD_ARGS="${PAYLOAD_ARGS:-tail -f /dev/null}"
CMD="cassandra -R"


function main() {
	local cmds=("docker")

	init_env
	check_cmds "${cmds[@]}"
	sudo -E docker pull "${DOCKER_IMAGE}"
	sudo -E docker save -o "${DOCKER_IMAGE}.tar" "${DOCKER_IMAGE}"
	sudo -E ctr i import "${DOCKER_IMAGE}.tar"

	sudo -E ctr run -d --runtime "${CTR_RUNTIME}" "${IMAGE}" "${CONTAINER_NAME}" sh -c "${PAYLOAD_ARGS}"
	sudo -E ctr t exec --exec-id 1 "${CONTAINER_NAME}" sh -c "${CMD}"
	local WRITE_CMD="./opt/cassandra/tools/bin/cassandra-stress write n=1000000 -rate threads=50"
	sudo -E ctr t exec --exec-id 2 "${CONTAINER_NAME}" sh -c "${WRITE_CMD}"

	clean_env_ctr
}

main "$@"
