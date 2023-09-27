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

target_dir="/usr/local/"
nydus_snapshotter_repo=$(get_version "externals.nydus-snapshotter.url")
nydus_snapshotter_version=$(get_version "externals.nydus-snapshotter.version")
nydus_snapshotter_repo_dir="${GOPATH}/src/github.com/containerd/nydus-snapshotter"
nydus_snapshotter_binary_target_dir="${target_dir}/bin"
nydus_snapshotter_config_target_dir="${target_dir}/share/nydus-snapshotter"

nydus_image_binary_target_dir="$nydus_snapshotter_binary_target_dir"
nydus_repo_dir="${GOPATH}/src/github.com/dragonflyoss/image-service"
nydus_repo=${nydus_repo:-"https://github.com/dragonflyoss/image-service"}
nydus_version=${nydus_version:-"main"}

arch="$(uname -m)"

clone_nydus_snapshotter_repo() {
    add_repo_to_git_safe_directory "${nydus_snapshotter_repo_dir}"

    if [ ! -d "${nydus_snapshotter_repo_dir}" ]; then
        mkdir -p "${nydus_snapshotter_repo_dir}"
        git clone ${nydus_snapshotter_repo} "${nydus_snapshotter_repo_dir}" || true
        pushd "${nydus_snapshotter_repo_dir}"
        git checkout "${nydus_snapshotter_version}"
        popd
    fi
}

clone_nydus_repo() {
    add_repo_to_git_safe_directory "${nydus_repo_dir}"

    if [ ! -d "${nydus_repo_dir}" ]; then
        mkdir -p "${nydus_repo_dir}"
        git clone ${nydus_repo} "${nydus_repo_dir}" || true
       if [ "$nydus_version" != "main" ];then
            pushd "${nydus_repo_dir}"
            git checkout "${nydus_version}"
            popd
       fi
    fi
}

build_nydus_snapshotter() {
    pushd "${nydus_snapshotter_repo_dir}"
    if [ "${arch}" = "s390x" ]; then
        export GOARCH=${arch}
    fi
    make

    sudo install -D -m 755 "bin/containerd-nydus-grpc" "${nydus_snapshotter_binary_target_dir}/containerd-nydus-grpc"
    sudo install -D -m 755 "bin/nydus-overlayfs" "${nydus_snapshotter_binary_target_dir}/nydus-overlayfs"
    rm -rf "${nydus_snapshotter_repo_dir}/bin"
    popd >/dev/null
}

build_nydus_image() {
    if [ "${arch}" = "s390x" ]; then
        echo "Skip to build nydus for ${arch}, it doesn't work for ${arch} now."
        return
    fi
    pushd "${nydus_repo_dir}"
    make release

    sudo install -D -m 755 "target/release/nydus-image" "${nydus_image_binary_target_dir}/nydus-image"
    rm -rf "${nydus_repo_dir}/target"
    popd >/dev/null
}

download_nydus_snapshotter_config() {
    tmp_dir=$(mktemp -d -t install-nydus-snapshotter-config-tmp.XXXXXXXXXX)
    curl -L https://raw.githubusercontent.com/containerd/nydus-snapshotter/${nydus_snapshotter_version}/misc/snapshotter/config-coco-guest-pulling.toml -o "${tmp_dir}/config-coco-guest-pulling.toml"
    curl -L https://raw.githubusercontent.com/containerd/nydus-snapshotter/${nydus_snapshotter_version}/misc/snapshotter/config-coco-host-sharing.toml -o "${tmp_dir}/config-coco-host-sharing.toml"
    sudo install -D -m 644 "${tmp_dir}/config-coco-guest-pulling.toml" "${nydus_snapshotter_config_target_dir}/config-coco-guest-pulling.toml"
    sudo install -D -m 644 "${tmp_dir}/config-coco-host-sharing.toml" "${nydus_snapshotter_config_target_dir}/config-coco-host-sharing.toml"

}

download_nydus_from_tarball() {
    if [ "${arch}" = "s390x" ]; then
        echo "Skip to download nydus for ${arch}, it doesn't work for ${arch} now."
        return
    fi
    
    local goarch="$(${cidir}/kata-arch.sh --golang)"
    local tarball_url="${nydus_repo}/releases/download/${nydus_version}/nydus-static-${nydus_version}-linux-${goarch}.tgz"
    echo "Download tarball from ${tarball_url}"
    tmp_dir=$(mktemp -d -t install-nydus-tmp.XXXXXXXXXX)
    curl -Ls "$tarball_url" | sudo tar xfz - -C ${tmp_dir} --strip-components=1
    sudo install -D -m 755 "${tmp_dir}/nydus-image" "${target_dir}/bin/"
}

clone_nydus_repo
#download_nydus_from_tarball
clone_nydus_snapshotter_repo
build_nydus_snapshotter
download_nydus_snapshotter_config
echo "install nydus-snapshotter successful"
