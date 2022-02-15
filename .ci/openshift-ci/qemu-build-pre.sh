#!/bin/bash
#
# Copyright (c) 2021 Red Hat Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
# This script is used to create a modified copy the QEMU dockerfile so that QEMU
# can be built on OpenShift CI build pipeline.
#

set -e

export GOPATH="${GOPATH:-/go}"
script_dir="$(realpath $(dirname $0))"
source "${script_dir}/../lib.sh"
pkg_dir="${katacontainers_repo_dir}/tools/packaging"

kata_version=${kata_version:-}
prefix=${PREFIX:-/opt/kata}

pushd "$pkg_dir" > /dev/null
source ./scripts/lib.sh
qemu_url=$(get_from_kata_deps "assets.hypervisor.qemu.url" "${kata_version}")

qemu_version=$(get_from_kata_deps "assets.hypervisor.qemu.version" "${kata_version}")

# Create a new dockerfile and replace the ARG statements with values
# from versions.yml.
cp -f static-build/qemu/{Dockerfile,Dockerfile.ci}
sed -i -e 's#\(ARG QEMU_REPO\).*#\1="'"$qemu_url"'"#' static-build/qemu/Dockerfile.ci
sed -i -e 's#\(ARG QEMU_VERSION\).*#\1="'${qemu_version}'"#' static-build/qemu/Dockerfile.ci
sed -i -e 's#\(ARG PREFIX\).*#\1="'${prefix}'"#' static-build/qemu/Dockerfile.ci
sed -i -e 's/\(ARG QEMU_TARBALL\).*/\1="kata-static-qemu.tar.gz"/' static-build/qemu/Dockerfile.ci
sed -i -e 's#\(ARG QEMU_DESTDIR\).*#\1="/tmp/qemu-static"#' static-build/qemu/Dockerfile.ci
popd
