#!/bin/bash
#
# Copyright (c) 2017-2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -e

cidir=$(dirname "$0")
source "${cidir}/lib.sh"

plugins_version=$(get_version "externals.cni-plugins.version")
echo "Retrieve CNI plugins repository"
pushd $GOPATH/src/
git clone https://github.com/containernetworking/plugins.git || true
cd plugins
git checkout "$plugins_version"

echo "Build CNI plugins"
sudo -E "PATH=$PATH" ./build_linux.sh

echo "Install CNI binaries"
cni_bin_path="/opt/cni"
sudo mkdir -p ${cni_bin_path}
sudo cp -a bin ${cni_bin_path}

popd
