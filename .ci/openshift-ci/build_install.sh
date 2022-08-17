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

export GOPATH="${GOPATH:-/go}"
export PATH="${GOPATH}/bin:/usr/local/go/bin/:$PATH"

cidir="$(dirname "$0")/.."
source /etc/os-release

source "${cidir}/lib.sh"

usage() {
	cat <<-EOF
	Usage: $0 path/to/install/dir

	This script is used by the CI job on OpenShift CI to build and install
	Kata Containers in a given directory.

	Environment variables:

	- Use SANDBOXED_CONTAINERS_CONF="yes" to configure like the OpenShift
	  Sandboxed Containers.
	EOF
}

if [ -z "$1" ]; then
	usage
	die "$0: missing parameter"
fi

export DESTDIR="$1"
info "Build and install Kata Containers at ${DESTDIR}"

[ "$(id -u)" -ne 0 ] && die "$0 must be executed by privileged user"

# This applies a set of build configurations akin to OpenShift
# Sandboxed Containers.
#
# The following environment variables have the origin on the Fedora rawhide
# specfile [*].
#
# [*] https://src.fedoraproject.org/rpms/kata-containers/blob/rawhide/f/kata-containers.spec
sandboxed_containers_build_configs() {
	export KERNELTYPE="compressed"
	export DEFSHAREDFS="virtio-fs"
	export DEFVIRTIOFSCACHESIZE=0
	export DEFSANDBOXCGROUPONLY=true
	export MACHINETYPE="q35"
	export FEATURE_SELINUX="yes"
	export DEFENABLEANNOTATIONS=['\".*\"']
}

# This ensures the guest image is built to work with the host Kernel akin to
# OpenShift Sandboxed Containers.
sandboxed_containers_image_configs() {
	# It needs to overwrite some variables of
	# kata-containers/tools/osbuilder/Makefile.
	export DRACUT_KVERSION="$(get_test_version "openshift-ci.dracut_kernel.version")"
	[ -n "$DRACUT_KVERSION" ] || \
		die "Unabled to get the kernel version from versions.yaml"
	export DRACUT_CONF_DIR=$(mktemp -d --tmpdir dracut.conf.d.XXXX)
	yum install -y "kernel-modules-${DRACUT_KVERSION}"
	# Unlike the kernel installed by the .ci/install_kata_kernel.sh script,
	# the host kernel doesn't have the needed modules built static. Thus,
	# we need to package them as loadable modules into the guest image.
	cp -r "${katacontainers_repo_dir}/tools/osbuilder/dracut/dracut.conf.d"/* \
		"${DRACUT_CONF_DIR}"
	cat <<-EOF >> "${DRACUT_CONF_DIR}/10-drivers.conf"
	drivers+="irqbypass "
	drivers+="vfio "
	drivers+="vfio_iommu_type1 "
	drivers+="vfio-pci "
	drivers+="vfio_virqfd "
	drivers+="virtio_blk "
	drivers+="virtio_console "
	drivers+="virtiofs "
	drivers+="virtio_net "
	drivers+="virtio_scsi "
	drivers+="vmw_vsock_virtio_transport "
	dracutmodules+=" bash rescue "
	EOF
}

# Let the scripts know it is in CI context.
export OPENSHIFT_CI="true"
export CI="true"

# This script is evoked within a variant of CentOS container image in the
# OpenShift Build process. So it was implemented for running in CentOS.
[[ "$ID" != "centos" || "$VERSION_ID" != "8" ]] && \
	die "Expect the build root to be CentOS 8"
# The scripts rely on tools which are not installed in the build
# environment and also the setup script doesn't install them.
yum install -y sudo git
"${cidir}/setup_env_centos.sh" default

# Install go suggested by Kata Containers.
"${cidir}/install_go.sh" -p -f

# Let's ensure scripts don't try things with Podman.
export TEST_CGROUPSV2="false"

# Configure to use the standard QEMU.
export experimental_qemu="false"

# Configure to use the initrd rootfs.
export TEST_INITRD="yes"

# Build a dracut-based image.
export BUILD_METHOD="dracut"

# Enable SELinux.
export FEATURE_SELINUX="yes"

# The default /usr prefix makes the deployment on Red Hat CoreOS (rhcos) more
# complex because that directory is read-only by design. Another prefix than
# /opt/kata is problematic too because QEMU either got from Kata Containers
# Jenkins or built locally is uncompressed in that directory.
export PREFIX="/opt/kata"

"${cidir}/install_kata_kernel.sh"

if [ "${SANDBOXED_CONTAINERS_CONF:-no}" == "yes" ]; then
	info "Apply build configurations akin to Openshift Sandboxed Containers"
	sandboxed_containers_build_configs
	sandboxed_containers_image_configs
fi

# osbuilder's make define a VERSION variable which value might clash with
# VERSION sourced from /etc/os-release.
unset VERSION
# It will be built a dracut-based rootfs so ensure dracut is installed in the
# build environment.
yum install -y dracut
"${cidir}/install_kata_image.sh"

"${cidir}/install_runtime.sh"

"${cidir}/install_virtiofsd.sh"

# The resulting kata installation will be merged in rhcos filesystem, and
# symlinks are troublesome. So instead let's convert them to in-place files.
for ltarget in $(find ${DESTDIR} -type l); do
	lsource=$(readlink -f "${ltarget}")
	if [ -e "${lsource}" ]; then
		unlink "${ltarget}"
		cp -fr "${lsource}" "${ltarget}"
	fi
done
