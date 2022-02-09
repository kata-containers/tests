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
export CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-containerd-shim-kata-v2}"
export CONTAINER_DEFAULT_RUNTIME="${CONTAINER_DEFAULT_RUNTIME:-$CONTAINER_RUNTIME}"
export RUNTIME_ROOT="${RUNTIME_ROOT:-/run/vc}"
export RUNTIME_TYPE="${RUNTIME_TYPE:-vm}"
export STORAGE_OPTIONS="--storage-driver overlay"
export PRIVILEGED_WITHOUT_HOST_DEVICES=true

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

# Clone CRI-O repo if it is not already present.
if [ ! -d "${crio_repository_path}" ]; then
	go get -d "${crio_repository}" || true
fi

# If the change we are testing does not come from CRI-O repository,
# then checkout to the version from versions.yaml in the runtime repository.
if [ "$ghprbGhRepository" != "${crio_repository/github.com\/}" ];then
	pushd "${crio_repository_path}"
	crio_version=$(get_version "externals.crio.branch")
	git fetch
	git checkout "${crio_version}"
	popd
fi

# Ensure the correct version of the CRI-O binary is built and ready
pushd "${crio_repository_path}"
CONTAINER_DEFAULT_RUNTIME="" make
make test-binaries
popd

OLD_IFS=$IFS
IFS=''

# Skip CRI-O tests that currently are not working
pushd "${crio_repository_path}/test/"

CRIO_VERSION=$(echo ${PULL_BASE_REF} | cut -d'-' -f 2)
if [ -z "$CRIO_VERSION" ]; then
    echo "Unknown version of cri-o - skipping more tests"
    CRIO_VERSION="1.21"
else
    echo GOT CRIO VERSION $CRIO_VERSION
fi

for batsfile in ${bats_files_list[@]}; do
    testfile=${batsfile%.*}_kata_integration_tests.bats
    cp ${batsfile} ${testfile}
    for testName in "${!skipCRIOTests[@]}"
    do
        echo "Skipping $testName in $testfile"
        sed -i '/'${testName}'/a skip \"'${skipCRIOTests[$testName]}'\"' "${testfile}"
    done

    # selectively skip tests depending on the version of cri-o we're testing with
    if [ "$CRIO_VERSION" != "main" ]; then
        for testName in "${!fixedInCrioVersion[@]}"
        do
            if [ "$(echo -e "$CRIO_VERSION\n${fixedInCrioVersion[$testName]}" | sort -V | head -n1)" != "${fixedInCrioVersion[$testName]}" ]; then
                echo "Skipping $testName in $testfile for cri-o v$CRIO_VERSION"
                sed -i '/'${testName}'/a skip \"- fixed in cri-o v'${fixedInCrioVersion[$testName]}'\"' "${testfile}"
            fi
        done
    fi
done

IFS=$OLD_IFS

echo "Ensure crio service is stopped before running the tests"
if systemctl is-active --quiet crio; then
	sudo systemctl stop crio
fi

echo "Ensure docker service is stopped before running the tests"
if systemctl is-active --quiet docker; then
	sudo systemctl stop docker
fi

echo "Running cri-o tests with runtime: $CONTAINER_RUNTIME"
./test_runner.sh *_kata_integration_tests.bats
rm *_kata_integration_tests.bats

popd
