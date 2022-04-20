#!/bin/bash
#
# Copyright (c) 2018 ARM Limited
#
# SPDX-License-Identifier: Apache-2.0

set -e

source "${cidir}/lib.sh"

CURRENT_QEMU_VERSION=$(get_version "assets.hypervisor.qemu.version")
CURRENT_QEMU_TAG=$(get_version "assets.hypervisor.qemu.tag")
QEMU_REPO_URL=$(get_version "assets.hypervisor.qemu.url")
# Remove 'https://' from the repo url to be able to git clone the repo
QEMU_REPO=${QEMU_REPO_URL/https:\/\//}

build_and_install_qemu() {
        PACKAGING_DIR="${katacontainers_repo_dir}/tools/packaging"
        QEMU_CONFIG_SCRIPT="${PACKAGING_DIR}/scripts/configure-hypervisor.sh"

	clone_qemu_repo
	clone_katacontainers_repo

        pushd "${GOPATH}/src/${QEMU_REPO}"
        sudo -E git fetch
        [ -d "capstone" ] || sudo -E git clone https://github.com/qemu/capstone.git --depth 1 capstone
        [ -d "ui/keycodemapdb" ] || sudo -E git clone  https://github.com/qemu/keycodemapdb.git --depth 1 ui/keycodemapdb

        # Apply required patches
	sudo -E ${PACKAGING_DIR}/scripts/patch_qemu.sh ${CURRENT_QEMU_VERSION} ${PACKAGING_DIR}/qemu/patches

        echo "Build Qemu"
        "${QEMU_CONFIG_SCRIPT}" "qemu" | xargs sudo -E ./configure
        sudo -E make -j $(nproc)

        echo "Install Qemu"
	sudo git config --global --add safe.directory $(pwd)
        sudo -E make install

        local qemu_bin=$(command -v qemu-system-${QEMU_ARCH})
        if [ $(dirname ${qemu_bin}) == "/usr/local/bin" ]; then
            # Add link from /usr/local/bin to /usr/bin
            sudo ln -sf $(command -v qemu-system-${QEMU_ARCH}) "/usr/bin/qemu-system-${QEMU_ARCH}"
        fi
	sudo mkdir -p /usr/libexec/kata-qemu/
	sudo ln -sf $(dirname ${qemu_bin})/../libexec/qemu/virtiofsd /usr/libexec/kata-qemu/virtiofsd
        popd
}
