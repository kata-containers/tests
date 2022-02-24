#!/usr/bin/env bats
#
# Copyright (c) 2022 Apple Inc.
#
# SPDX-License-Identifier: Apache-2.0
#

IMAGE="${IMAGE:-quay.io/prometheus/busybox:latest}"
CONTAINER_NAME="${CONTAINER_NAME:-kataocihookstest}"
CTR_RUNTIME="io.containerd.kata.v2"

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

readonly KATA_CONFIG="${KATA_CONFIG:-/etc/kata-containers/configuration.toml}"
readonly KATA_CONFIG_BACKUP="$KATA_CONFIG.backup"
readonly DEFAULT_KATA_CONFIG="/usr/share/defaults/kata-containers/configuration.toml"

function teardown() {
	sudo rm -rf $HOST_TMP_TEST_DIR
	[ -f "$KATA_CONFIG_BACKUP" ] && sudo mv "$KATA_CONFIG_BACKUP" "$KATA_CONFIG" || \
		sudo cp "$DEFAULT_KATA_CONFIG" "$KATA_CONFIG"
}

function setup() {
	HOST_TMP_TEST_DIR="$(mktemp -d)"
	sudo mkdir -p $(dirname "${KATA_CONFIG}")
	[ -f "$KATA_CONFIG" ] && sudo cp "$KATA_CONFIG" "$KATA_CONFIG_BACKUP" || \
		sudo cp "$DEFAULT_KATA_CONFIG" "$KATA_CONFIG"
}

function test_hook_works() {
	hook_type=$1

	local tmp_guest_img_path="$HOST_TMP_TEST_DIR/kata-containers.img"
	local tmp_hooks_filepath="$HOST_TMP_TEST_DIR/hooks.sh"
	local tmp_mount_point="$HOST_TMP_TEST_DIR/mnt"
	local tmp_oci_hooks_file="/tmp/test-oci-hooks-file"

	# leveraging an OCI hook so that we can inspect the file after the container is up and running.
	local tmp_oci_hooks_dir="$tmp_mount_point/usr/share/oci/hooks/$hook_type"

	# add file with greppable phrase to file that is shared by guest vm and container.
	printf "#!/bin/sh\necho \"foo\" > /run/kata-containers/%s/rootfs/$tmp_oci_hooks_file\n" "$CONTAINER_NAME" > $tmp_hooks_filepath
	chmod +x $tmp_hooks_filepath

	# prepare guest image with hooks
	mkdir $tmp_mount_point
	cp /usr/share/kata-containers/kata-containers.img $tmp_guest_img_path
	sudo mount -o loop,offset=$((512*6144)) $tmp_guest_img_path $tmp_mount_point
	sudo mkdir -p $tmp_oci_hooks_dir
	sudo cp $tmp_hooks_filepath $tmp_oci_hooks_dir
	sudo umount $tmp_mount_point

	# add guest image to config file and enable oci hooks.
	sudo sed -i -r "s#^(image =).*#\1 \"$tmp_guest_img_path\"#" "$KATA_CONFIG"
	sudo sed -i '/^#guest_hook_path /s/^#//' "$KATA_CONFIG"

	# pull an image with ctr to run and test for oci hooks
	sudo ctr image pull "$IMAGE" || die "Unable to get image $IMAGE"

	run sudo ctr run --rm --runtime="$CTR_RUNTIME" "$IMAGE" "$CONTAINER_NAME" sh -c "grep foo $tmp_oci_hooks_file"
	[ "$status" -eq 0 ]
}


@test "Ensure prestart OCI hooks work" {
	test_hook_works "prestart"
}

@test "Ensure poststart OCI hooks work" {
	test_hook_works "poststart"
}

