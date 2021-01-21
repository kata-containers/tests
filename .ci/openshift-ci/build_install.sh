#!/bin/bash
#
# Copyright (c) 2020 Red Hat, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
# This script is evoked within an OpenShift Build to product the binary image,
# which will contain the Kata Containers installation into a given destination
# directory.
#

set -e

export PATH="${GOPATH}/bin:$PATH"

cidir="$(dirname "$0")/.."
source /etc/os-release

source "${cidir}/lib.sh"

[ -z "$1" ] && die "Usage: $0 path/to/install/dir"
export DESTDIR="$1"
info "Build and install Kata Containers at ${DESTDIR}"

[ "$(id -u)" -ne 0 ] && die "$0 must be executed by privileged user"

# Let the scripts know it is in OpenShift CI context.
export OPENSHIFT_CI="true"

# This script is evoked within a variant of CentOS container image in the
# OpenShift Build process. So it was implemented for running in CentOS.
[ "$ID" != "centos" ] && die "Expect the build root to be CentOS"
# The scripts rely on sudo which is not installed in the build environment.
yum install -y sudo
"${cidir}/setup_env_centos.sh" default

# The build root container has already golang installed, let's remove it
# so that it will use the version required by kata.
yum remove -y golang
"${cidir}/install_go.sh" -p -f

# Let's ensure scripts don't try things with Podman.
export TEST_CGROUPSV2="false"

# Configure to use the standard QEMU.
export experimental_qemu="false"
export experimental_kernel="false"

# Configure to use the initrd rootfs.
export TEST_INITRD="yes"

# Build a dracut-based image.
export BUILD_METHOD="dracut"

# Configure to use vsock.
export USE_VSOCK="yes"

# Configure the QEMU machine type.
export MACHINETYPE="q35"

# Enable SELinux.
export FEATURE_SELINUX="yes"

# The default /usr prefix makes the deployment on Red Hat CoreOS (rhcos) more
# complex because that directory is read-only by design. Another prefix than
# /opt/kata is problematic too because QEMU either got from Kata Containers
# Jenkins or built locally is uncompressed in that directory.
export PREFIX="/opt/kata"

"${cidir}/install_kata_kernel.sh"

# osbuilder's make define a VERSION variable which value might clash with
# VERSION sourced from /etc/os-release.
unset VERSION
"${cidir}/install_kata_image.sh"

"${cidir}/install_runtime.sh"
config_file="${DESTDIR}/${PREFIX}/share/defaults/kata-containers/configuration.toml"
# TODO: currently the virtio-fs backend cannot be tested on OpenShift.
# See issue https://github.com/kata-containers/kata-containers/issues/1238
if [ -f "$config_file" ]; then
	sed -i 's|^shared_fs = "virtio-fs"|shared_fs = "virtio-9p"|g' "$config_file"
fi
