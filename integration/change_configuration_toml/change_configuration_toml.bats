#!/usr/bin/env bats
#
# Copyright (c) 2020 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

load "${BATS_TEST_DIRNAME}/../../lib/common.bash"
default_kata_config="/usr/share/defaults/kata-containers/configuration.toml"
image="busybox"
payload="tail -f /dev/null"
container_name="test-configuration"

tmp_data_dir="$(mktemp -d)"
CONFIG_FILE="${tmp_data_dir}/configuration.toml"

setup() {
	clean_env
	run check_processes
	echo "$output"
	cp -a "${default_kata_config}" "${CONFIG_FILE}"
}

@test "bad machine type" {
	sudo sed -i 's|^machine_type.*|machine_type = "foo"|g' "${default_kata_config}"
	run docker run -d --name "${container_name}" --runtime "${RUNTIME}" "${image}" sh -c "${payload}"
	echo "$output"
	[ "$status" -ne 0 ]
}

teardown() {
	docker rm -f "${container_name}"
	cp -a "${CONFIG_FILE}" "${default_kata_config}"
	sudo rm -rf "${tmp_data_dir}"
	clean_env
	run check_processes
	echo "$output"
}
