#!/bin/bash
#
# Copyright (c) 2019 IBM Limited
#
# SPDX-License-Identifier: Apache-2.0

set -e

CURRENT_QEMU_TAG=$(get_version "assets.hypervisor.qemu.tag")
stable_branch=$(echo $CURRENT_QEMU_TAG | tr -d 'v' | awk 'BEGIN { FS = "." } {print $1 "." $2 ".x"}')
BUILT_QEMU="qemu-system-ppc64"
export source_repo="${source_repo:-github.com/kata-containers/kata-containers}"
export packaging_dir="$GOPATH/src/${source_repo}/tools/packaging"

source "${cidir}/lib.sh"

build_and_install_qemu() {
        QEMU_REPO_URL=$(get_version "assets.hypervisor.qemu.url")
        # Remove 'https://' from the repo url to be able to clone the repo using 'go get'
        QEMU_REPO=${QEMU_REPO_URL/https:\/\//}
        PACKAGING_DIR="${katacontainers_repo_dir}/tools/packaging"
        QEMU_CONFIG_SCRIPT="${PACKAGING_DIR}/scripts/configure-hypervisor.sh"

        sudo -E git clone --branch "$CURRENT_QEMU_TAG" --depth 1 "$QEMU_REPO_URL" "${GOPATH}/src/${QEMU_REPO}"

        clone_katacontainers_repo

        pushd "${GOPATH}/src/${QEMU_REPO}"
        sudo -E git fetch

        [ -d "capstone" ] || sudo -E git clone https://github.com/qemu/capstone.git capstone
        [ -d "ui/keycodemapdb" ] || sudo -E git clone  https://github.com/qemu/keycodemapdb.git ui/keycodemapdb
	
        sudo -E ${packaging_dir}/scripts/apply_patches.sh "${packaging_dir}/qemu/patches/${stable_branch}"
	
        echo "Build Qemu"
        "${QEMU_CONFIG_SCRIPT}" "qemu" | xargs sudo -E ./configure
        sudo -E make -j $(nproc)

        echo "Install Qemu"
        sudo -E make install

        sudo ln -sf $(command -v ${BUILT_QEMU}) "/usr/bin/qemu-system-${QEMU_ARCH}"

        echo "Link virtiofsd to /usr/libexec/kata-qemu/virtiofsd"
        ls -l $(pwd)/build/tools/virtiofsd/virtiofsd || return 1
        sudo mkdir -p /usr/libexec/kata-qemu/
        sudo ln -sf $(pwd)/build/tools/virtiofsd/virtiofsd /usr/libexec/kata-qemu/virtiofsd
        ls -l /usr/libexec/kata-qemu/virtiofsd || return 1
        popd
}
