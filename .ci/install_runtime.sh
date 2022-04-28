#!/bin/bash
#
# Copyright (c) 2017-2020 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

cidir=$(dirname "$0")

source "${cidir}/lib.sh"
source /etc/os-release || source /usr/lib/os-release
KATACONTAINERS_REPO=${katacontainers_repo:="github.com/kata-containers/kata-containers"}
KATA_HYPERVISOR="${KATA_HYPERVISOR:-qemu}"
KATA_EXPERIMENTAL_FEATURES="${KATA_EXPERIMENTAL_FEATURES:-}"
MACHINETYPE="${MACHINETYPE:-q35}"
METRICS_CI="${METRICS_CI:-}"
PREFIX="${PREFIX:-/usr}"
DESTDIR="${DESTDIR:-/}"
TEST_INITRD="${TEST_INITRD:-}"
USE_VSOCK="${USE_VSOCK:-yes}"
TEE_TYPE="${TEE_TYPE:-}"

arch=$("${cidir}"/kata-arch.sh -d)

# Modify the runtimes build-time defaults

# enable verbose build
export V=1

# tell the runtime build to use sane defaults
export SYSTEM_BUILD_TYPE=kata

# The runtimes config file should live here
export SYSCONFDIR=/etc

# Artifacts (kernel + image) live below here
export SHAREDIR=${PREFIX}/share

# Whether running on OpenShift CI or not.
OPENSHIFT_CI="${OPENSHIFT_CI:-false}"

runtime_config_path="${SYSCONFDIR}/kata-containers/configuration.toml"
runtime_src_path="${GOPATH}/src/${KATACONTAINERS_REPO}/src/runtime"

PKGDEFAULTSDIR="${DESTDIR}${SHAREDIR}/defaults/kata-containers"
NEW_RUNTIME_CONFIG="${PKGDEFAULTSDIR}/configuration.toml"
# Note: This will also install the config file.

build_install_shim_v2(){
	if [ ! -d "$runtime_src_path" ]; then
		go get "$KATACONTAINERS_REPO"
	fi
	pushd "$runtime_src_path"
	make
	sudo -E PATH=$PATH make install
	popd
}

build_install_shim_v2

experimental_qemu="${experimental_qemu:-false}"

if [ -e "${NEW_RUNTIME_CONFIG}" ]; then
	# Remove the legacy config file
	sudo rm -f "${runtime_config_path}"

	# Use the new path
	runtime_config_path="${NEW_RUNTIME_CONFIG}"
fi

enable_hypervisor_config(){
	local path=$1
	sudo rm -f "${PKGDEFAULTSDIR}/configuration.toml"
	sudo cp -a "$path" "${PKGDEFAULTSDIR}/configuration.toml"

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
			enable_hypervisor_config "${PKGDEFAULTSDIR}/configuration-qemu.toml"
		if [ "$arch" == "x86_64" ]; then
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
	image_path="${image_path:-$SHAREDIR/kata-containers}"
	initrd_name=${initrd_name:-kata-containers-initrd.img}
	sudo sed -i -e "s|^image =.*|initrd = \"$image_path/$initrd_name\"|" "${runtime_config_path}"
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

	# On OpenShift CI the vhost module should not be loaded on build time.
	if [ "$OPENSHIFT_CI" == "false" ]; then
		vsock_module="vhost_vsock"
		echo "Check if ${vsock_module} is loaded"
		if lsmod | grep -q "\<${vsock_module}\>" ; then
			echo "Module ${vsock_module} is already loaded"
		else
			echo "Load ${vsock_module} module"
			sudo modprobe "${vsock_module}"
		fi
	fi
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

# Install UEFI ROM for arm64/qemu
ENABLE_ARM64_UEFI="${ENABLE_ARM64_UEFI:-false}"
if [ "$arch" == "aarch64" -a "${KATA_HYPERVISOR}" == "qemu" -a "${ENABLE_ARM64_UEFI}" == "true" ]; then
	${cidir}/aarch64/install_rom_aarch64.sh
	sudo sed -i 's|pflashes = \[\]|pflashes = ["/usr/share/kata-containers/kata-flash0.img", "/usr/share/kata-containers/kata-flash1.img"]|' "${runtime_config_path}"
	#enable pflash
	sudo sed -i 's|#pflashes|pflashes|' "${runtime_config_path}"
fi

if [ "$TEE_TYPE" == "tdx" ]; then
        echo "Use tdx enabled guest config in ${runtime_config_path}"
        sudo sed -i -e 's/vmlinux.container/vmlinuz-tdx.container/' "${runtime_config_path}"
        sudo sed -i -e 's/^# confidential_guest/confidential_guest/' "${runtime_config_path}"
        sudo sed -i -e 's/^kernel_params = "\(.*\)"/kernel_params = "\1 force_tdx_guest tdx_disable_filter "/g' "${runtime_config_path}"

        case "${KATA_HYPERVISOR}" in
		"cloud-hypervisor")
			sudo sed -i -e 's/^firmware = ".*"/firmware = "\/usr\/share\/td-shim\/final-pe.bin"/' "${runtime_config_path}"
			;;

		"qemu")
			sudo sed -i -e 's/^firmware = ".*"/firmware = "\/usr\/share\/qemu\/OVMF.fd"/' "${runtime_config_path}"
			sudo sed -i -e 's/^firmware_volume = ".*"/firmware_volume = "\/usr\/share\/qemu\/OVMF_VARS.fd"/' "${runtime_config_path}"
			;;
        esac
fi
