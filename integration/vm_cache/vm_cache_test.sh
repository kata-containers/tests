#!/bin/bash
#
# Copyright (c) 2019 Intel Corporation.
#
# SPDX-License-Identifier: Apache-2.0
#
# This test will perform several tests to validate kata containers with
# vm cache.

set -e

cidir=$(dirname "$0")

source "${cidir}/../../metrics/lib/common.bash"

# Environment variables
IMAGE="${IMAGE:-busybox}"
PAYLOAD_ARGS="${PAYLOAD_ARGS:-tail -f /dev/null}"
kata_runtime_bin=$(command -v kata-runtime)

if [ -z $INITRD_PATH ]; then
	echo "Skipping vm templating test as initrd is not set"
	exit 0
fi

enable_vm_cache_config() {
	echo "enable vm cache config"
	sudo sed -i 's/#vm_cache_number = 0/vm_cache_number = 1/g' "${RUNTIME_CONFIG_PATH}"
	sudo sed -i -e 's/^#\(use_vsock\).*=.*$/\1 = true/g' "${RUNTIME_CONFIG_PATH}"
}

disable_vm_cache_config() {
	echo "disable vm cache config"
	sudo sed -i 's/vm_cache_number = 1/#vm_cache_number = 0/g' "${RUNTIME_CONFIG_PATH}"
	sudo sed -i -e 's/^\(use_vsock\).*=.*$/#\1 = true/g' "${RUNTIME_CONFIG_PATH}"
}

init_vm_template() {
	sudo sed -i -e 's/^#enable_template.*$/enable_template = true/g' "${RUNTIME_CONFIG_PATH}"
	echo "init vm template"
	sudo -E PATH=$PATH "$kata_runtime_bin" factory init &
	pid=$!
	sudo kill -9 $pid
}

destroy_vm_template() {
	echo "destroy vm template"
	sudo -E PATH=$PATH "$kata_runtime_bin" factory destroy
}

setup() {
	clean_env
	extract_kata_env
	enable_vm_cache_config
	init_vm_template
}

test_docker_vm_cache() {
	docker run -d --runtime $RUNTIME $IMAGE $PAYLOAD_ARGS
	check_initrd=$(ps aux | grep ${HYPERVISOR_PATH} | grep initrd)
	[ ! -z "${check_initrd}" ] || die "vm cache not running properly"
}

teardown() {
	clean_env
	disable_vm_cache_config
}


echo "Starting vm cache test"
setup

echo "Running vm cache test"
test_docker_vm_cache

echo "Ending vm cache test"
teardown
