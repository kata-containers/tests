#!/bin/bash
#
# Copyright (c) 2020 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

dir_path=$(dirname "$0")
source "${dir_path}/../../lib/common.bash"
source "${dir_path}/../../.ci/lib.sh"
source /etc/os-release || source /usr/lib/os-release
image="fedora"
payload="tail -f /dev/null"
container_name="test-pmem"
osbuilder_repository="github.com/kata-containers/osbuilder"
osbuilder_repository_path="${GOPATH}/src/${osbuilder_repository}"
test_directory_name="test_pmem1"
test_directory=$(mktemp -d --suffix="${test_directory_name}")
TEST_INITRD="${TEST_INITRD:-no}"
experimental_qemu="${experimental_qemu:-false}"

if [ "$TEST_INITRD" == "yes" ]; then
	echo "Skip pmem test: nvdimm is disabled when initrd is used as rootfs"
	exit 0
fi

if [ "$experimental_qemu" == "true" ]; then
	echo "Skip pmem test: experimental qemu doesn't have libpmem support"
	exit 0
fi

function setup() {
	clean_env
	check_processes
	if [ ! -d "${osbuilder_repository_path}" ]; then
		go get -d "${osbuilder_repository}" || true
	fi
}

function test_pmem {
	"${dir_path}/../../cmd/pmemctl/pmemctl.sh" -s 128M -f xfs -m "${test_directory}" xfs.img

	# Running container
	docker run -d --name "${container_name}" --runtime kata-runtime -v "${test_directory}:/${test_directory_name}" "${image}" sh -c "${payload}"

	# Check container
	docker exec "${container_name}" sh -exc "mount | grep ${test_directory_name} | grep '/dev/pmem' | grep 'dax'"
}

function teardown() {
	clean_env
	check_processes
	sudo umount "${test_directory}"
	sudo losetup -D
	sudo rm -rf "${test_directory}"
}

trap teardown EXIT

echo "Running setup"
setup

echo "Running pmem test"
test_pmem
