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
IMAGE="${IMAGE:-fstest}"
DOCKERFILE="${SCRIPT_PATH}/Dockerfile"
CONT_NAME="${CONT_NAME:-fstest}"
RUNTIME="${RUNTIME:-kata-runtime}"
PAYLOAD_ARGS="${PAYLOAD_ARGS:-tail -f /dev/null}"

function main() {
	clean_env
	check_dockerfiles_images "$IMAGE" "$DOCKERFILE"
	ctr run --rm --runtime=${CTR_RUNTIME} $IMAGE test $CMD

	docker exec $CONT_NAME bash -c "cd /pjdfstest && prove -r"

	clean_env
}

main "$@"
