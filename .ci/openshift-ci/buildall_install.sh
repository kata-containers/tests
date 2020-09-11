#!/bin/bash
#
# Copyright (c) 2020 Red Hat, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
# This script is evoked within an OpenShift Build to product the binary image,
# which will contain the Kata Containers installation into a give destination
# directory.
#

set -e

export PATH="${GOPATH}/bin:$PATH"

cidir="$(dirname "$0")/.."
source /etc/os-release || source /usr/lib/os-release
source "${cidir}/lib.sh"

[ -z "$1" ] && die "Usage: $0 path/to/install/dir"
export DESTDIR="$1"
info "Build and install Kata Containers at ${DESTDIR}"

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

# Configure to use vsock.
# TODO: install_runtime.sh will try to load the vsock module and the script
# fail. See https://github.com/kata-containers/tests/issues/2614
#export USE_VSOCK="yes"

# Configure the QEMU machine type.
export MACHINETYPE="q35"

# Disable SELinux.
export FEATURE_SELINUX="no"

# The default /usr prefix makes the deployment on Red Hat CoreOS (rhcos) more
# complex because that directory is read-only by design. Another prefix than
# /opt/kata is problematic too because QEMU experimental eventually got from
# Kata Containers Jenkins is uncompressed in that directory.
export PREFIX="/opt/kata"

RUN_KATA_CHECK="false" "${cidir}/install_kata.sh"

# The resulting kata installation will be merged in rhcos filesystem, and
# symlinks are troublesome. So instead let's convert them to in-place files.
for ltarget in $(find ${DESTDIR} -type l); do
	lsource=$(readlink -f "${ltarget}")
	if [ -e "${lsource}" ]; then
		unlink "${ltarget}"
		cp -fr "${lsource}" "${ltarget}"
	fi
done

# The standard QEMU cached in Jenkins is built with /usr/bin prefix, thus it
# needs to adjust the binary path in configuration.toml.
if [ "${PREFIX}" == "/opt/kata" ]; then
	sed -i -e 's|^path = "/opt/kata/bin/\(qemu-.*\)"|path = "/usr/bin/\1"|'\
		${DESTDIR}/opt/kata/share/defaults/kata-containers/configuration.toml
fi
