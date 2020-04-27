#!/bin/bash
#
# Copyright (c) 2017-2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -e

cidir=$(dirname "$0")
source "${cidir}/lib.sh"
BATS_REPO="github.com/bats-core/bats-core"
version=$(get_test_version "externals.bats.version")

echo "Install BATS from sources"
go get -d "${BATS_REPO}" || true
pushd "${GOPATH}/src/${BATS_REPO}"
# This is related with https://github.com/bats-core/bats-core/issues/290
# and with https://github.com/bats-core/bats-core/issues/292
git checkout "${version}"
sudo -E PATH=$PATH sh -c "./install.sh /usr"
popd
