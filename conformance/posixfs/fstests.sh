#!/bin/bash
#
# Copyright (c) 2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

set -e

# General env
SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_PATH}/../../metrics/lib/common.bash"
source "${SCRIPT_PATH}/../../lib/common.bash"

# Env variables
IMAGE="docker.io/library/local-fstest:latest"
DOCKERFILE="${SCRIPT_PATH}/Dockerfile"
CONT_NAME="${CONT_NAME:-fstest}"
RUNTIME="${RUNTIME:-kata-runtime}"
PAYLOAD_ARGS="${PAYLOAD_ARGS:-tail -f /dev/null}"

function main() {
	check_ctr_images "$IMAGE" "$DOCKERFILE"
	ctr run --rm --runtime=${CTR_RUNTIME} $IMAGE fstest bash -c "cd /pjdfstest && prove -r"
}

main "$@"
