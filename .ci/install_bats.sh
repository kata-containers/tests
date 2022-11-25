#!/bin/bash
#
# Copyright (c) 2017-2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -e

which bats && exit

BATS_REPO="https://github.com/bats-core/bats-core.git"

echo "Install BATS from sources"
pushd "${GOPATH}/src/"
git clone "${BATS_REPO}" || true
cd bats-core
sudo -E PATH=$PATH sh -c "./install.sh /usr"
popd
