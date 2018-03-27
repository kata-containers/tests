#!/bin/bash
#
# Copyright (c) 2017-2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -e

cidir=$(dirname "$0")

OSBUILDER_DISTRO=${OSBUILDER_DISTRO:-clearlinux}
image_name="kata-containers.img"

# Build Kata agent
bash -f ${cidir}/install_agent.sh

osbuilder_repo="github.com/kata-containers/osbuilder"

# Clone os-builder repository
go get -d ${osbuilder_repo} || true

pushd "${GOPATH}/src/${osbuilder_repo}/rootfs-builder"
sudo -E GOPATH=$GOPATH USE_DOCKER=true ./rootfs.sh ${OSBUILDER_DISTRO}
popd

# Build the image
pushd "${GOPATH}/src/${osbuilder_repo}/image-builder"
sudo -E USE_DOCKER=true ./image_builder.sh ../rootfs-builder/rootfs

# Install the image
agent_commit=$("$GOPATH/src/github.com/kata-containers/agent/kata-agent" --version | awk '{print $NF}')
commit=$(git log --format=%h -1 HEAD)
date=$(date +%Y-%m-%d-%T.%N%z)
image="kata-containers-${date}-osbuilder-${commit}-agent-${agent_commit}"

sudo install -o root -g root -m 0640 -D ${image_name} "/usr/share/kata-containers/${image}"
(cd /usr/share/kata-containers && sudo ln -sf "$image" ${image_name})

popd
