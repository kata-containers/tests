#!/bin/bash
#
# Copyright (c) 2017-2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -e

cidir=$(dirname "$0")

source "${cidir}/lib.sh"
source /etc/os-release || source /usr/lib/os-release
KATA_HYPERVISOR="${KATA_HYPERVISOR:-qemu}"
MACHINETYPE="${MACHINETYPE:-pc}"
TEST_CGROUPSV2="${TEST_CGROUPSV2:-false}"

arch=$("${cidir}"/kata-arch.sh -d)

# Modify the runtimes build-time defaults

# enable verbose build
export V=1
tag="$1"

# tell the runtime build to use sane defaults
export SYSTEM_BUILD_TYPE=kata

# The runtimes config file should live here
export SYSCONFDIR=/etc

if [ -n "${PREFIX}" ]; then
	SHAREDIR=${DESTDIR:-}${PREFIX}/share
else
	SHAREDIR=${DESTDIR:-}/usr/share
fi

# Artifacts (kernel + image) live below here
export SHAREDIR

USE_VSOCK="${USE_VSOCK:-no}"

runtime_config_path="${SYSCONFDIR}/kata-containers/configuration.toml"

PKGDEFAULTSDIR="${SHAREDIR}/defaults/kata-containers"
NEW_RUNTIME_CONFIG="${PKGDEFAULTSDIR}/configuration.toml"
# Note: This will also install the config file.
build_and_install "${runtime_repo}" "" "true" "${tag}"
experimental_qemu="${experimental_qemu:-false}"

if [ -e "${NEW_RUNTIME_CONFIG}" ]; then
	# Remove the legacy config file
	sudo rm -f "${runtime_config_path}"

	# Use the new path
	runtime_config_path="${NEW_RUNTIME_CONFIG}"
fi

enable_hypervisor_config(){
	local path=$1
	sudo ln -f "$path" "${PKGDEFAULTSDIR}/configuration.toml"

}

case "${KATA_HYPERVISOR}" in
	"acrn")
		enable_hypervisor_config "${PKGDEFAULTSDIR}/configuration-acrn.toml"
		;;
	"cloud-hypervisor")
		enable_hypervisor_config "${PKGDEFAULTSDIR}/configuration-clh.toml"
		;;
	"firecracker")
		enable_hypervisor_config "${PKGDEFAULTSDIR}/configuration-fc.toml"
		;;
	"qemu")
		if [ "$experimental_qemu" == "true" ]; then
			enable_hypervisor_config "${PKGDEFAULTSDIR}/configuration-qemu-virtiofs.toml"
		else
			enable_hypervisor_config "${PKGDEFAULTSDIR}/configuration-qemu.toml"
		fi
		if [ "$CI" == true ] && [ "$(uname -m)" == "x86_64" ]; then
			# Due to a KVM bug, vmx-rdseed-exit must be disabled in QEMU >= 4.2
			# All CI now uses qemu 5.0+, disabled in the time..
			# see https://github.com/kata-containers/runtime/pull/2355#issuecomment-625469252
			sudo sed -i 's|^cpu_features="|cpu_features="-vmx-rdseed-exit,|g' "${runtime_config_path}"
		fi
		;;
	*)
		die "failed to enable config for '${KATA_HYPERVISOR}', not supported"
		;;
esac

if [ x"${TEST_INITRD}" == x"yes" ]; then
	echo "Set to test initrd image"
	sudo sed -i -e '/^image =/d' ${runtime_config_path}
else
	echo "Set to test rootfs image"
	sudo sed -i -e '/^initrd =/d' ${runtime_config_path}
fi

if [ -z "${METRICS_CI}" ]; then
	echo "Enabling all debug options in file ${runtime_config_path}"
	sudo sed -i -e 's/^#\(enable_debug\).*=.*$/\1 = true/g' "${runtime_config_path}"
	sudo sed -i -e 's/^kernel_params = "\(.*\)"/kernel_params = "\1 agent.log=debug"/g' "${runtime_config_path}"
else
	echo "Metrics run - do not enable all debug options in file ${runtime_config_path}"
fi

if [ "$USE_VSOCK" == "yes" ]; then
	echo "Configure use of VSOCK in ${runtime_config_path}"
	sudo sed -i -e 's/^#use_vsock.*/use_vsock = true/' "${runtime_config_path}"

	vsock_module="vhost_vsock"
	echo "Check if ${vsock_module} is loaded"
	if lsmod | grep -q "$vsock_module" &> /dev/null ; then
		echo "Module ${vsock_module} is already loaded"
	else
		echo "Load ${vsock_module} module"
		sudo modprobe "${vsock_module}"
	fi
fi

if [ "${TEST_CGROUPSV2}" == "false" ]; then
	case "${KATA_HYPERVISOR}" in
		"cloud-hypervisor" | "qemu" | "firecracker")
			echo "Add kata-runtime as a new Docker runtime."
			if command -v docker >/dev/null; then
				"${cidir}/../cmd/container-manager/manage_ctr_mgr.sh" docker configure -r kata-runtime -f
			else
				echo "Docker is not installed, skipping..."
			fi
			;;
		*)
			echo "Kata runtime will not be set in Docker"
			;;
	esac
fi

if [ "$MACHINETYPE" == "q35" ]; then
	echo "Use machine_type q35"
	sudo sed -i -e 's|machine_type = "pc"|machine_type = "q35"|' "${runtime_config_path}"
fi

# Enable experimental features if KATA_EXPERIMENTAL_FEATURES is set to true
if [ "$KATA_EXPERIMENTAL_FEATURES" = true ]; then
	echo "Enable runtime experimental features"
	feature="newstore"
	sudo sed -i -e "s|^experimental.*$|experimental=[ \"$feature\" ]|" "${runtime_config_path}"
fi

# Enable virtio-blk device driver only for ubuntu with initrd for this moment
# see https://github.com/kata-containers/tests/issues/1603
if [ "$ID" == ubuntu ] && [ x"${TEST_INITRD}" == x"yes" ] && [ "$VERSION_ID" != "16.04" ] && [ "$arch" != "ppc64le" ]; then
	echo "Set virtio-blk as the block device driver on $ID"
	sudo sed -i 's/block_device_driver = "virtio-scsi"/block_device_driver = "virtio-blk"/' "${runtime_config_path}"
fi
