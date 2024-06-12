#!/bin/bash
#
# Copyright (c) 2022 Kata Contributors
#
# SPDX-License-Identifier: Apache-2.0
#
# This will run a containers and then check
# whether the kata-agent is working properly with systemd cgroup.

set -e
set -o errexit
set -o nounset
set -o pipefail

[ -n "$BASH_VERSION" ] && set -o errtrace
[ -n "${DEBUG:-}" ] && set -o xtrace

DIR_PATH=$(dirname "$0")
source "${DIR_PATH}/../../lib/common.bash"
source "${DIR_PATH}/../../metrics/lib/common.bash"

TMP_DATA_DIR="$(mktemp -d)"
ROOTFS_TAR="${TMP_DATA_DIR}/rootfs.tar"
BUNDLE_DIR="${TMP_DATA_DIR}/bundle"

pull_rootfs() {
	local image="quay.io/prometheus/busybox:latest"
	sudo -E ctr i pull ${image}
	sudo -E ctr i export "${ROOTFS_TAR}" "${image}"
	sudo chown ${USER}:${USER} "${ROOTFS_TAR}"
	sync
}

create_bundle() {
	mkdir -p "${BUNDLE_DIR}"

	# rootfs
	local ROOTFS_DIR="${BUNDLE_DIR}/rootfs"
	mkdir -p "${ROOTFS_DIR}"
	local LAYERS_DIR="$(mktemp -d)"
	tar -C "${LAYERS_DIR}" -pxf "${ROOTFS_TAR}"
	for ((i=0;i<$(cat ${LAYERS_DIR}/manifest.json | jq -r ".[].Layers | length");i++)); do
		tar -C ${ROOTFS_DIR} -xf ${LAYERS_DIR}/$(cat ${LAYERS_DIR}/manifest.json | jq -r ".[].Layers[${i}]")
	done
	rm -rf "${LAYERS_DIR}"

	# config.json
	sed -e '/^#.*/d' \
		-e 's|@ROOTFS@|'"${BUNDLE_DIR}/rootfs"'|g' \
		"${DIR_PATH}/systemd_config.json.in" > "${BUNDLE_DIR}/config.json"
	
	sync
}

setup() {
	pull_rootfs
	create_bundle
	restart_containerd_service
	check_processes
}

test_systemd_agent() {
	local CONTAINER_ID="test_systemd_agent-${RANDOM}"

	sudo -E ctr run -d --runtime io.containerd.kata.v2 --config "${BUNDLE_DIR}/config.json" "${CONTAINER_ID}"

	local CGROUP_VERSION=$(sudo ctr t exec --exec-id test ${CONTAINER_ID} sh -c '(ls /sys/fs/cgroup/pids >> /dev/null 2>&1 && echo v1) || echo v2')
	if [ "$CGROUP_VERSION" = "v1" ]
	then
		memory_limit=$(sudo ctr t exec --exec-id test ${CONTAINER_ID} sh -c 'cat /sys/fs/cgroup/memory/memory.limit_in_bytes')
	else
		memory_limit=$(sudo ctr t exec --exec-id test ${CONTAINER_ID} sh -c 'cat /sys/fs/cgroup/system.slice/memory.max')
	fi
	
	[ "$memory_limit" == "713687040" ] || die "systemd cgroup failed to limit memory"

	sudo -E ctr task kill -s SIGKILL "${CONTAINER_ID}"
	sudo -E ctr c rm "${CONTAINER_ID}"
}

teardown() {
	clean_env_ctr
	check_processes
}

trap teardown EXIT

echo "Running setup"
setup

echo "Running integration tests with systemd agent"
test_systemd_agent
