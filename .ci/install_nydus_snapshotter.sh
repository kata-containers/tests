#!/bin/bash
#
# Copyright (c) 2023 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail

cidir=$(dirname "$0")
source "${cidir}/lib.sh"
source "${cidir}/../lib/common.bash"

source "/etc/os-release" || source "/usr/lib/os-release"
KATA_HYPERVISOR="${KATA_HYPERVISOR:-qemu}"
TEE_TYPE="${TEE_TYPE:-}"
PKGDEFAULTSDIR="${PKGDEFAULTSDIR:-/opt/kata/share/defaults/kata-containers}"
DEFAULT_CONFIG_FILE="$PKGDEFAULTSDIR/configuration-qemu.toml"
CONTAINERD_CONFIG_FILE="/etc/containerd/config.toml"

arch="$(uname -m)"
if [ "$arch" != "x86_64" ]; then
	echo "Skip installation for $arch, it only works for x86_64 now. See https://github.com/kata-containers/tests/issues/4445"
	exit 0
fi

function install_from_tarball() {
	local package_name="$1"
	local binary_name="$2"
	[ -n "$package_name" ] || die "need package_name"
	[ -n "$binary_name" ] || die "need package release binary_name"

	local url=$(get_version "externals.${package_name}.url")
	local version=$(get_version "externals.${package_name}.version")
	local tarball_url="${url}/releases/download/${version}/${binary_name}-${version}-$arch.tgz"
	if [ "${package_name}" == "nydus" ]; then
		local goarch="$(${dir_path}/../../.ci/kata-arch.sh --golang)"
		tarball_url="${url}/releases/download/${version}/${binary_name}-${version}-linux-$goarch.tgz"
	fi
	echo "Download tarball from ${tarball_url}"
	curl -Ls "$tarball_url" | sudo tar xfz - -C /usr/local/bin --strip-components=1
}

function setup_nydus() {
	# install nydus
	install_from_tarball "nydus" "nydus-static"

	# install nydus-snapshotter
	install_from_tarball "nydus-snapshotter" "nydus-snapshotter"

	# Config nydus snapshotter
	sudo -E cp "${cidir}/integration/nydus/nydusd-config.json" /etc/

	# start nydus-snapshotter
	nohup /usr/local/bin/containerd-nydus-grpc \
		--config-path /etc/nydusd-config.json \
		--log-level debug \
		--root /var/lib/containerd/io.containerd.snapshotter.v1.nydus \
		--cache-dir /var/lib/nydus/cache \
		--nydusd-path /usr/local/bin/nydusd \
		--nydusimg-path /usr/local/bin/nydus-image \
		--disable-cache-manager true \
		--enable-nydus-overlayfs true \
		--log-to-stdout >/dev/null 2>&1 &
}

function config_kata() {
	if [ "$KATA_HYPERVISOR" == "qemu" ]; then
		case "$TEE_TYPE" in
		"tdx") DEFAULT_CONFIG_FILE="${PKGDEFAULTSDIR}/configuration-qemu-tdx.toml" ;;
		"sev") DEFAULT_CONFIG_FILE="${PKGDEFAULTSDIR}/configuration-qemu-sev.toml" ;;
		"snp") DEFAULT_CONFIG_FILE="${PKGDEFAULTSDIR}/configuration-qemu-snp.toml" ;;
		"se") DEFAULT_CONFIG_FILE="${PKGDEFAULTSDIR}/configuration-qemu-se.toml" ;;
		esac
		sudo sed -i 's|^virtio_fs_extra_args.*|virtio_fs_extra_args = []|g' "${DEFAULT_CONFIG_FILE}"
	else
		if [ "$TEE_TYPE" == "tdx" ]; then
			DEFAULT_CONFIG_FILE="${PKGDEFAULTSDIR}/configuration-clh-tdx.toml"
		fi
		sudo sed -i 's|^virtio_fs_extra_args.*|virtio_fs_extra_args = []|g' "${DEFAULT_CONFIG_FILE}"
	fi
}

function config_containerd() {
	sed -i 's/\[proxy_plugins\]/\[proxy_plugins\]\n \[proxy_plugins.nydus\]\n type = "snapshot"\n address = "\/run\/containerd-nydus\/containerd-nydus-grpc.sock"/' "$CONTAINERD_CONFIG_FILE"
	sed -i 's/snapshotter = "overlayfs"/snapshotter = "nydus"/' "$CONTAINERD_CONFIG_FILE"
	sed -i 's/disable_snapshot_annotations = true/disable_snapshot_annotations = false/' "$CONTAINERD_CONFIG_FILE"
}

function check_nydus_snapshotter_process() {
	bin=containerd-nydus-grpc
	if pgrep -f "$bin"; then
		echo "nydus snapshotter is running"
	else
		echo "nydus snapshotter is not running"
		exit 1
	fi
}

function setup() {
	setup_nydus
	config_kata
	config_containerd
	restart_containerd_service
	check_processes
	check_nydus_snapshotter_process
}

setup
