#!/bin/bash
#
# Copyright (c) 2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -e

cidir=$(dirname "$0")
source /etc/os-release || source /usr/lib/os-release
source "${cidir}/lib.sh"

echo "Install chronic"
sudo -E dnf -y install moreutils

chronic sudo -E dnf -y install dnf-plugins-core
chronic sudo -E dnf makecache

echo "Install test dependencies"
chronic sudo -E dnf -y install python

echo "Install kata containers dependencies"
chronic sudo -E dnf -y groupinstall "Development tools"
chronic sudo -E dnf -y install libtool automake autoconf bc pixman numactl-libs

echo "Install qemu dependencies"
chronic sudo -E dnf -y install libcap-devel libattr-devel \
	libcap-ng-devel zlib-devel pixman-devel librbd-devel

echo "Install nemu dependencies"
chronic sudo -E dnf -y install brlapi

echo "Install kernel dependencies"
chronic sudo -E dnf -y install elfutils-libelf-devel flex

echo "Install CRI-O dependencies"
chronic sudo -E dnf -y install btrfs-progs-devel device-mapper-devel      \
	glib2-devel glibc-devel glibc-static gpgme-devel libassuan-devel  \
	libgpg-error-devel libseccomp-devel libselinux-devel ostree-devel \
	pkgconfig util-linux

echo "Install bison binary"
chronic sudo -E dnf -y install bison

echo "Install YAML validator"
chronic sudo -E dnf -y install yamllint

echo "Install tools for metrics tests"
chronic sudo -E dnf -y install smem jq

if [ "$(arch)" == "x86_64" ]; then
	echo "Install Kata Containers OBS repository"
	obs_url="${KATA_OBS_REPO_BASE}/Fedora_$VERSION_ID/home:katacontainers:releases:$(arch):master.repo"
	sudo -E VERSION_ID=$VERSION_ID dnf config-manager --add-repo "$obs_url"
fi

echo "Install cri-containerd dependencies"
chronic sudo -E dnf -y install libseccomp-devel btrfs-progs-devel libseccomp-static

echo "Install crudini"
chronic sudo -E dnf -y install crudini

echo "Install procenv"
chronic sudo -E dnf -y install procenv

echo "Install haveged"
chronic sudo -E dnf -y install haveged

echo "Install GNU parallel"
chronic sudo -E dnf -y install parallel

if [ "$KATA_KSM_THROTTLER" == "yes" ]; then
	echo "Install ${KATA_KSM_THROTTLER_JOB}"
	chronic sudo -E dnf -y install ${KATA_KSM_THROTTLER_JOB}
fi
