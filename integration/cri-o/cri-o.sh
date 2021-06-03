#!/bin/bash
#
# Copyright (c) 2017-2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -e

SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_PATH}/../../.ci/lib.sh"
source "${SCRIPT_PATH}/crio_skip_tests.sh"
source "${SCRIPT_PATH}/../../metrics/lib/common.bash"
source /etc/os-release || source /usr/lib/os-release

export JOBS="${JOBS:-$(nproc)}"
export CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-$RUNTIME}"

# Skip the cri-o tests if TEST_CRIO is not true
# and we are on a CI job.
# For non CI execution, run the cri-o tests always.
if [ "$CI" = true ] && [ "$TEST_CRIO" != true ]
then
	echo "Skipping cri-o tests as TEST_CRIO is not true"
	exit
fi

crio_repository="github.com/cri-o/cri-o"
crio_repository_path="$GOPATH/src/${crio_repository}"

img_file=""
loop_device=""
cleanup() {
	[ -n "${loop_device}" ] && sudo losetup -d "${loop_device}"
	[ -n "${img_file}" ] && rm -f "${img_file}"
}

# Check no processes are left behind
check_processes

# overlay storage options
OVERLAY_STORAGE_OPTIONS="--storage-driver overlay"

# Clone CRI-O repo if it is not already present.
if [ ! -d "${crio_repository_path}" ]; then
	go get -d "${crio_repository}" || true
fi

# If the change we are testing does not come from CRI-O repository,
# then checkout to the version from versions.yaml in the runtime repository.
if [ "$ghprbGhRepository" != "${crio_repository/github.com\/}" ];then
	pushd "${crio_repository_path}"
	if [ "$ID" == "fedora" ]; then
		crio_version=$(get_version "externals.crio.meta.openshift")
	else
		crio_version=$(get_version "externals.crio.version")
	fi
	git fetch
	git checkout "${crio_version}"
	popd
fi

OLD_IFS=$IFS
IFS=''

# Skip CRI-O tests that currently are not working
pushd "${crio_repository_path}/test/"
for i in "${skipCRIOTests[@]}"
do
	sed -i '/'${i}'/a skip \"This is not working\"' "$GOPATH/src/${crio_repository}/test/ctr.bats"
done

IFS=$OLD_IFS

# On other distros or on ZUUL, use overlay.
# This will allow us to run tests with at least 2 different
# storage drivers.
export STORAGE_OPTIONS="$OVERLAY_STORAGE_OPTIONS"

echo "Ensure crio service is stopped before running the tests"
if systemctl is-active --quiet crio; then
	sudo systemctl stop crio
fi

echo "Ensure docker service is stopped before running the tests"
if systemctl is-active --quiet docker; then
	sudo systemctl stop docker
fi

echo "Running cri-o tests with runtime: $CONTAINER_RUNTIME"
./test_runner.sh ctr.bats

popd
