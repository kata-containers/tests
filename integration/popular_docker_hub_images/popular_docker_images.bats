#!/usr/bin/env bats
# *-*- Mode: sh; sh-basic-offset: 8; indent-tabs-mode: nil -*-*
#
# Copyright (c) 2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#
# Tests for the most popular images from docker hub.

source ${BATS_TEST_DIRNAME}/../../lib/common.bash

versions_file="${BATS_TEST_DIRNAME}/../../versions.yaml"
kibana_version=$("${GOPATH}/bin/yq" read "$versions_file" "docker_images.kibana.version")
kibana_image="docker.io/library/kibana:$kibana_version"

setup() {
	# Check that processes are not running
	run check_ctr_shim_processes
	echo "$output"
	[ "$status" -eq 0 ]
	clean_env_ctr
}

@test "[display text] hello world in an alpine container" {
	image="docker.io/library/alpine:latest"
	sudo ctr image pull $image
	sudo ctr run --rm --runtime=$RUNTIME -t $image foobar sh -c "echo 'Hello, World':latest"
}

@test "[teamspeak] run a teamspeak container" {
	image="docker.io/library/teamspeak:latest"
	sudo ctr image pull $image
	sudo ctr run --rm --runtime=$RUNTIME -t --env TS3SERVER_LICENSE=accept $image foobar sh -c "printf 'Kata Containers':latest"
}

@test "[run application] run an instance in an ubuntu debootstrap container" {
	image="docker.io/library/ubuntu-debootstrap:latest"
	sudo ctr image pull $image
	sudo ctr run --rm --runtime=$RUNTIME -t $image foobar sh -c 'if [ -f /etc/bash.bashrc ]; then echo "/etc/bash.bashrc exists"; fi'
}

@test "[run application] start server in a vault container" {
	image="docker.io/library/vault:latest"
	sudo ctr image pull $image
	sudo ctr run --rm --runtime=$RUNTIME -t --env 'VAULT_DEV_ROOT_TOKEN_ID=mytest' $image foobar timeout 10 vault server -dev
}

@test "[perl application] start wordpress container" {
	image="docker.io/library/wordpress:latest"
	sudo ctr image pull $image
	if sudo ctr run --rm --runtime=$RUNTIME -t $image foobar perl -e 'print "test\n"' | grep LANG; then false; else true; fi
}

@test "[run application] start zookeeper container" {
	image="docker.io/library/zookeeper:latest"
	sudo ctr image pull $image
	sudo ctr run --rm --runtime=$RUNTIME -t $image foobar zkServer.sh
}

teardown() {
	clean_env_ctr
	sudo ctr image rm $image
	# Check that processes are not running
	run check_ctr_shim_processes
	echo "$output"
	[ "$status" -eq 0 ]
}
