#!/usr/bin/env bats
# Copyright (c) 2023 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

load "${BATS_TEST_DIRNAME}/tests_common.sh"

tag_suffix=""
if [ "$(uname -m)" != "x86_64" ]; then
    tag_suffix="-$(uname -m)"
fi

# Images used on the tests.

image_unsigned_protected="quay.io/kata-containers/confidential-containers:unsigned${tag_suffix}"

original_kernel_params=$(get_kernel_params)
# Allow to configure the runtimeClassName on pod configuration.
RUNTIMECLASS="${RUNTIMECLASS:-kata}"
test_tag="[cc][agent][kubernetes][containerd]"

setup() {
    remove_test_image "$image_unsigned_protected" || true
    setup_containerd
    restart_containerd
    configure_containerd_for_nydus_snapshotter "/etc/containerd/config.toml"
    reconfigure_kata
    switch_image_service_offload off
}

@test "$test_tag Test can pull an image as a raw block disk image to guest with dm-verity enabled" {
    if [ "$(uname -m)" = "s390x" ]; then
        skip "test for s390x as nydus-image doesn't currently support this platform"
    fi
    if [ "$SNAPSHOTTER" = "nydus" ]; then
        EXPORT_MODE="image_block_with_verity" RUNTIMECLASS="$RUNTIMECLASS" configure_remote_snapshotter
        pod_config="$(new_pod_config "$image_unsigned_protected")"
        echo $pod_config
        create_test_pod
    fi
}

@test "$test_tag Test can pull an image as a raw block disk image to guest without dm-verity" {
    if [ "$(uname -m)" = "s390x" ]; then
        skip "test for s390x as nydus-image doesn't currently support this platform"
    fi
    if [ "$SNAPSHOTTER" = "nydus" ]; then
        EXPORT_MODE="image_block" configure_remote_snapshotter
        pod_config="$(new_pod_config "$image_unsigned_protected")"
        echo $pod_config
        create_test_pod
    fi
}

@test "$test_tag Test can pull an image inside the guest with remote-snapshotter" {
    switch_image_service_offload on
    if [ "$SNAPSHOTTER" = "nydus" ]; then
        EXPORT_MODE="image_guest_pull" RUNTIMECLASS="$RUNTIMECLASS" SNAPSHOTTER="nydus" configure_remote_snapshotter
        pod_config="$(new_pod_config "$image_unsigned_protected")"
        echo $pod_config
        create_test_pod
    fi
}

teardown() {
    teardown_common
    remove_test_image "$image_unsigned_protected" || true
    kill_nydus_snapshotter_process
    unset_vanilla_containerd
}
