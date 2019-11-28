#!/bin/bash
#
# Copyright (c) 2020 ARM Limited
#
# SPDX-License-Identifier: Apache-2.0

set -o errexit
set -o nounset
set -o pipefail

cidir=$(dirname "$0")
source "${cidir}/../../metrics/lib/common.bash"

kata_runtime=$(command -v kata-runtime)

# Environment variables
KATA_CACHE_INIT="${kata_runtime} factory init"
KATA_CACHE_STATUS="${kata_runtime} factory status"
KATA_CACHE_DESTROY="${kata_runtime} factory destroy"
KATA_CACHE_SOCK="/var/run/kata-containers/cache.sock"

IMAGE="${IMAGE:-busybox}"
TEST_PLAYLOAD="2"
CONTAINER_NAME=$(random_name)
PAYLOAD_ARGS="${PAYLOAD_ARGS:-tail -f /dev/null}"

setup() {
        extract_kata_env
}

teardown(){
	IFS="", stale_process_union=("${KATA_CACHE_INIT}" "${HYPERVISOR_PATH}")
	for stale_process in ${stale_process_union[@]}
	do
		local pid=$(pgrep -f "${stale_process}")
		if [ -n "${pid}" ]; then
			echo "${pid}" | xargs kill
		fi
	done

	if [ -e ${KATA_CACHE_SOCK} ]; then
		sudo sh -c 'rm -f ${KATA_CACHE_SOCK}'
	fi
}

enable_vm_cache_config() {
	echo "enable vm cache config ${RUNTIME_CONFIG_PATH}"
	sudo sed -i -e 's/^#\(vm_cache_number\).*=.*$/\1 = 2/g' "${RUNTIME_CONFIG_PATH}"
	sudo sed -i -e 's/^#\(vm_cache_endpoint =.*\)$/\1/g' "${RUNTIME_CONFIG_PATH}"
}

disable_vm_cache_config() {
	echo "disable vm cache config ${RUNTIME_CONFIG_PATH}"
	sudo sed -i -e 's/^\(vm_cache_number =.*\)$/#\1/g' "${RUNTIME_CONFIG_PATH}"
	sudo sed -i -e 's/^\(vm_cache_endpoint =.*\)$/#\1/g' "${RUNTIME_CONFIG_PATH}"
}

init_vm_cache_server() {
	echo "init vm cache server"
	# launch vm cache server in background.
	${KATA_CACHE_INIT} &
	# give cache server two seconds for fully running
	sleep 2

	check_qemu_for_vm_cache_server ${TEST_PLAYLOAD}
}

destroy_vm_cache_server() {
	echo "destroy vm cache server"
	local res=$(${KATA_CACHE_DESTROY})

	[[ $res =~ "vm factory destroyed" ]] || die "fail to destroy cache server!"
	check_qemu_for_vm_cache_server 0
}

check_qemu_for_vm_cache_server() {
	local qemu_status="$1"
        echo "checking qemu status"

	local res=$(pgrep -f ${HYPERVISOR_PATH} | wc -l)
	[ "$res" == "${qemu_status}" ] || die "qemu status is not satisfied!"
}

check_vm_cache_server_status() {
	echo "checking vm cache server status"
	local status=$(${KATA_CACHE_STATUS})

	local test_server_pid=$(echo "$status" | awk ' /VM cache server/ {print $6} ')
	local actual_server_pid=$(pgrep -f "${KATA_CACHE_INIT}")
	[ "$test_server_pid" == "$actual_server_pid" ] || die "fail to display correct VM cache server status!"

	local test_vms_pid=$(echo "$status" | awk ' /VM pid/ {printf "%s,",$4} ')
	IFS=',', read -r -a test_vms_pid_array <<< "${test_vms_pid}"
	local actual_vms_pid="$(pgrep -d " " -f "${HYPERVISOR_PATH}")"
	for vm_pid in ${test_vms_pid_array[@]}
	do
		[[ "${actual_vms_pid}" =~ "${vm_pid}" ]] || die "fail to display correct VM status!"
	done
}

check_new_guest_date_time() {
	HOSTTIME=$(date +%s)
	GUESTTIME=$(docker exec $CONTAINER_NAME date +%s)
	[[ ${HOSTTIME} -le ${GUESTTIME} ]] || die "hosttime ${HOSTTIME} guesttime ${GUESTTIME}"
}

test_create_container_with_vm_cache() {
	echo "test creating kata container with vm cache factory"
	docker run --runtime=$RUNTIME -d --name $CONTAINER_NAME $IMAGE $PAYLOAD_ARGS
	check_new_guest_date_time
	docker rm -f $CONTAINER_NAME
}

test_vm_cache_factory_init_destroy() {
	enable_vm_cache_config
	init_vm_cache_server
	check_vm_cache_server_status
	test_create_container_with_vm_cache
	destroy_vm_cache_server
	disable_vm_cache_config
}

main() {
	echo "Starting vm cache test"
	setup

	trap teardown EXIT

	echo "Running vm cache test"
	test_vm_cache_factory_init_destroy
}

main "$@"
