#!/bin/bash
#
# Copyright (c) 2022 Kata Contributors
#
# SPDX-License-Identifier: Apache-2.0
#
# This test will validate runk with containerd

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

dir_path=$(dirname "$0")
source /etc/os-release || source /usr/lib/os-release
source "${dir_path}/../../../lib/common.bash"
source "${dir_path}/../../../.ci/lib.sh"
source "${dir_path}/../../../metrics/lib/common.bash"

KATACONTAINERS_REPO=${katacontainers_repo:="github.com/kata-containers/kata-containers"}
RUNK_SRC_PATH="${GOPATH}/src/${KATACONTAINERS_REPO}/src/tools/runk"
RUNK_BIN_PATH="/usr/local/bin/runk"
TEST_IMAGE="docker.io/library/busybox:latest"
CONTAINER_ID="id1"
PID_FILE="${CONTAINER_ID}.pid"

# runk can't work well on cgroup V2 environment now, so we temporarily skip this test
if [ $(stat -f --format %T /sys/fs/cgroup) == "cgroup2fs" ]; then
    echo "runk can't work well on cgroup V2 environment now, so we temporarily skip this test"
    exit 0
fi

setup() {
    # can't find cargo when make runk below, so we install rust to make runk build correctly
    "${dir_path}/../../../.ci/install_rust.sh" && source "$HOME/.cargo/env"
    echo "restart containerd service"
    sudo systemctl restart containerd
    echo "pull container image"
    check_images ${TEST_IMAGE}
}

install_runk() {
    echo "Install runk"
    pushd ${RUNK_SRC_PATH}
    make
    sudo make install
    popd
}

test_runk() {
    echo "start container with runk"
    sudo ctr run --pid-file ${PID_FILE} --rm -d --runc-binary ${RUNK_BIN_PATH} ${TEST_IMAGE} ${CONTAINER_ID}
    read CID PID STATUS <<< $(sudo ctr t ls | grep ${CONTAINER_ID})
    [ ${PID} == $(cat ${PID_FILE}) ] || die "pid is not consistent"
    [ ${STATUS} == "RUNNING" ] || die "contianer status is not RUNNING"

    echo "exec process in a container"
    sudo ctr t exec --exec-id id1 ${CONTAINER_ID} sh -c "echo hello > /tmp/foo"
    [ "hello" == "$(sudo ctr t exec --exec-id id1 ${CONTAINER_ID} cat /tmp/foo)" ] || die "exec process failed"

    echo "test ps command"
    sudo ctr t exec --detach --exec-id id1 ${CONTAINER_ID} sh
    # one line is the titles, and the other 2 lines are porcess info
    [ "3" == "$(sudo ctr t ps ${CONTAINER_ID} | wc -l)" ] || die "ps command failed"

    echo "kill the container and poll until it is stopped"
    sudo ctr t kill --signal SIGKILL --all ${CONTAINER_ID}
    # poll for a while until the task receives signal and exit
    local cmd='[ "STOPPED" == "$(sudo ctr t ls | grep ${CONTAINER_ID} | awk "{print \$3}")" ]'
    waitForProcess 10 1 "${cmd}" || die "failed to kill task"

    echo "check the container is stopped, and delete it"
    # there is only title line of ps command
    [ "1" == "$(sudo ctr t ps ${CONTAINER_ID} | wc -l)" ] || die "kill command failed"
    sudo ctr t rm ${CONTAINER_ID} || die "failed to delete task"
    [ -z "$(sudo ctr t ls | grep ${CONTAINER_ID})" ] || die "failed to delete task"
    sudo ctr c rm ${CONTAINER_ID} || die "failed to delete container"
}

clean_up() {
    rm -f ${PID_FILE}
}

setup
install_runk
test_runk
clean_up
