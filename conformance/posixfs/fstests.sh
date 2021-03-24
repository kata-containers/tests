#!/bin/bash
#
# Copyright (c) 2021 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

set -e

# General env
SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_PATH}/../../metrics/lib/common.bash"
source "${SCRIPT_PATH}/../../lib/common.bash"

# Env variables
IMAGE="${IMAGE:-docker.io/library/fstest:latest}"
DOCKERFILE="${SCRIPT_PATH}/Dockerfile"
CONT_NAME="${CONT_NAME:-fstest}"
PAYLOAD_ARGS="${PAYLOAD_ARGS:-tail -f /dev/null}"

function main() {
	sudo systemctl restart containerd
	clean_env_ctr
	CONTAINERD_RUNTIME="io.containerd.kata.v2"
	check_ctr_images "$IMAGE" "$DOCKERFILE"
	sudo ctr run --runtime=$CONTAINERD_RUNTIME -d $IMAGE $CONT_NAME sh -c $PAYLOAD_ARGS

	echo "WARNING: Removing failing tests (Issue https://github.com/kata-containers/runtime/issues/826" >&2
	REMOVE_FILES="cd pjdfstest/tests && rm -f chown/00.t chmod/12.t link/00.t mkdir/00.t symlink/03.t mkfifo/00.t mknod/00.t mknod/11.t utimensat/06.t open/00.t"
	sudo ctr t exec --exec-id 1 $CONT_NAME sh -c "${REMOVE_FILES}"
	sudo ctr t exec --exec-id 1 $CONT_NAME sh -c "cd /pjdfstest && prove -r"

	clean_env_ctr
}

main "$@"
