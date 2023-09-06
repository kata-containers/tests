#!/bin/bash
#
# Copyright (c) 2023 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

cidir=$(dirname "$0")
source "${cidir}/lib.sh"

target_dir="/opt/confidential-containers"

nydus_snapshotter_repo=${nydus_snapshotter_repo:-"github.com/containerd/nydus-snapshotter"}
nydus_snapshotter_repo_git="https://${nydus_snapshotter_repo}.git"
nydus_snapshotter_version=${nydus_snapshotter_version:-"v0.12.0"}
nydus_snapshotter_repo_dir="${GOPATH}/src/${nydus_snapshotter_repo}"
nydus_snapshotter_binary_target_dir="$target_dir/bin"
nydus_snapshotter_config_target_dir="$target_dir/share/nydus-snapshotter"

nydus_repo=${nydus_repo:-"https://github.com/dragonflyoss/image-service"}
nydus_version=${nydus_version:-"v2.2.3"}

arch="$(uname -m)"

clone_nydus_snapshotter_repo() {
    add_repo_to_git_safe_directory "${nydus_snapshotter_repo_dir}"

    if [ ! -d "${nydus_snapshotter_repo_dir}" ]; then
        sudo mkdir -p "${nydus_snapshotter_repo_dir}"
        git clone ${nydus_snapshotter_repo_git} "${nydus_snapshotter_repo_dir}" || true
        pushd "${nydus_snapshotter_repo_dir}"
        git checkout "${nydus_snapshotter_version}"
        popd
    fi
}

build_nydus_snapshotter() {
    pushd "${nydus_snapshotter_repo_dir}"
    if [ "$arch" = "s390x" ]; then
        export GOARCH=$arch
    fi
    sudo -E PATH=$PATH make

    if [ ! -d "$nydus_snapshotter_binary_target_dir" ]; then
        sudo mkdir -p $nydus_snapshotter_binary_target_dir
    fi
    sudo install -D -m 755 "bin/containerd-nydus-grpc" "$nydus_snapshotter_binary_target_dir/containerd-nydus-grpc"
    sudo install -D -m 755 "bin/nydus-overlayfs" "$nydus_snapshotter_binary_target_dir/nydus-overlayfs"
    if [ ! -f "/usr/local/bin/nydus-overlayfs" ]; then
        echo " /usr/local/bin/nydus-overlayfs exists, now we will replace it."
        sudo cp -f "$nydus_snapshotter_binary_target_dir/nydus-overlayfs" "/usr/local/bin/nydus-overlayfs"
    fi
    sudo rm -rf "$nydus_snapshotter_repo_dir/bin"
    popd >/dev/null
}

download_nydus_snapshotter_config() {
    if [ ! -d "$nydus_snapshotter_config_target_dir" ]; then
        mkdir -p "$nydus_snapshotter_config_target_dir"
    fi
    sudo curl -L https://raw.githubusercontent.com/containerd/nydus-snapshotter/main/misc/snapshotter/config-coco-guest-pulling.toml -o "$nydus_snapshotter_config_target_dir/config-coco-guest-pulling.toml"
    sudo curl -L https://raw.githubusercontent.com/containerd/nydus-snapshotter/main/misc/snapshotter/config-coco-host-sharing.toml -o "$nydus_snapshotter_config_target_dir/config-coco-host-sharing.toml"
    sudo chmod 644 "$nydus_snapshotter_config_target_dir/config-coco-guest-pulling.toml"
    sudo chmod 644 "$nydus_snapshotter_config_target_dir/config-coco-host-sharing.toml"

}

download_nydus_from_tarball() {
    if [ "$arch" = "s390x" ]; then
        echo "Skip to download nydus for $arch, it doesn't work for $arch now."
        return
    fi
    local goarch="$(${cidir}/kata-arch.sh --golang)"
    local tarball_url="${nydus_repo}/releases/download/${nydus_version}/nydus-static-${nydus_version}-linux-$goarch.tgz"
    echo "Download tarball from ${tarball_url}"
    tmp_dir=$(mktemp -d -t install-nydus-tmp.XXXXXXXXXX)
    curl -Ls "$tarball_url" | sudo tar xfz - -C $tmp_dir --strip-components=1
    sudo install -D -m 755 "$tmp_dir/nydus-image" "/usr/local/bin/"
}

download_nydus_from_tarball
clone_nydus_snapshotter_repo
build_nydus_snapshotter
download_nydus_snapshotter_config
echo "install nydus-snapshotter successful"
