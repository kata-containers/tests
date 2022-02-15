#!/bin/bash
#
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

cidir=$(dirname "$0")
source "${cidir}/lib.sh"
source "${cidir}/../lib/common.bash"
source /etc/os-release || source /usr/lib/os-release

KATA_DEV_MODE="${KATA_DEV_MODE:-}"

CURRENT_QEMU_TAG=$(get_version "assets.hypervisor.qemu-experimental.version")
PACKAGING_DIR="${katacontainers_repo_dir}/tools/packaging"
QEMU_TAR="kata-static-qemu-experimental.tar.gz"
arch=$("${cidir}"/kata-arch.sh -d)
qemu_experimental_latest_build_url="${jenkins_url}/job/qemu-experimental-nightly-$(uname -m)/${cached_artifacts_path}"

bindir="${DESTDIR:-}/usr/bin"
libexecdir="${DESTDIR:-}/usr/libexec/"

QEMU_PATH="/opt/kata/bin/qemu-system-x86_64-experimental"
DEST_QEMU_PATH="${bindir}/qemu-system-$(uname -m)"
VIRTIOFSD_PATH="/opt/kata/libexec/kata-qemu-experimental/virtiofsd-experimental"
DEST_VIRTIOFSD_PATH="${libexecdir}/kata-qemu/virtiofsd"

uncompress_experimental_qemu() {
	local qemu_tar_location="$1"
	[ -n "$qemu_tar_location" ] || die "provide the location of the QEMU compressed file"
	sudo tar -xvf "${qemu_tar_location}" -C /
}

install_cached_qemu_experimental() {
	info "Installing cached experimental QEMU"
	curl -fL --progress-bar "${qemu_experimental_latest_build_url}/${QEMU_TAR}" -o "${QEMU_TAR}" || return 1
	curl -fsOL "${qemu_experimental_latest_build_url}/sha256sum-${QEMU_TAR}" || return 1
	sha256sum -c "sha256sum-${QEMU_TAR}" || return 1
	uncompress_experimental_qemu "${QEMU_TAR}"
	sudo mkdir -p "${KATA_TESTS_CACHEDIR}"
	sudo mv "${QEMU_TAR}" "${KATA_TESTS_CACHEDIR}"
}

build_and_install_static_experimental_qemu() {
	build_experimental_qemu
	uncompress_experimental_qemu "${KATA_TESTS_CACHEDIR}/${QEMU_TAR}"
}

build_experimental_qemu() {
	mkdir -p "${GOPATH}/src"
	clone_katacontainers_repo
	"${PACKAGING_DIR}/static-build/qemu/build-static-qemu-experimental.sh"
	sudo mkdir -p "${KATA_TESTS_CACHEDIR}"
	sudo mv "${QEMU_TAR}" "${KATA_TESTS_CACHEDIR}"
}

main() {
	if [ "$arch" != "x86_64" ]; then
		die "Unsupported architecture: $arch"
	fi
	cached_qemu_experimental_version=$(curl -sfL "${qemu_experimental_latest_build_url}/latest") || cached_qemu_experimental_version="none"
	info "Cached qemu experimental version: $cached_qemu_experimental_version"
	info "Current qemu experimental version: $CURRENT_QEMU_TAG"
	if [ "$cached_qemu_experimental_version" == "$CURRENT_QEMU_TAG" ]; then
		install_cached_qemu_experimental || build_and_install_static_experimental_qemu
	else
		build_and_install_static_experimental_qemu
	fi
	info "Symlink experimental qemu to default qemu path"
	[ -e "${QEMU_PATH}" ] || die "not found ${QEMU_PATH} after install tarball "
	[ -e "${VIRTIOFSD_PATH}" ] || die "not found ${VIRTIOFSD_PATH} after install tarball "
	info "${QEMU_PATH} -> ${DEST_QEMU_PATH}"
	sudo -E ln -sf "${QEMU_PATH}" "${DEST_QEMU_PATH}"
	info "${VIRTIOFSD_PATH} -> ${DEST_VIRTIOFSD_PATH}"
	sudo mkdir -p $(dirname "${DEST_VIRTIOFSD_PATH}")
	sudo -E ln -sf "${VIRTIOFSD_PATH}" "${DEST_VIRTIOFSD_PATH}"
}

main
