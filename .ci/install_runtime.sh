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
KATA_BUILD_CC="${KATA_BUILD_CC:-no}"
KATA_HYPERVISOR="${KATA_HYPERVISOR:-qemu}"
KATA_EXPERIMENTAL_FEATURES="${KATA_EXPERIMENTAL_FEATURES:-}"
MACHINETYPE="${MACHINETYPE:-q35}"
METRICS_CI="${METRICS_CI:-}"
if [ "$KATA_BUILD_CC" == "yes" ]; then
	PREFIX="${PREFIX:-/opt/confidential-containers}"
fi
PREFIX="${PREFIX:-/opt/kata}"
DESTDIR="${DESTDIR:-/}"
TEST_INITRD="${TEST_INITRD:-}"
USE_VSOCK="${USE_VSOCK:-yes}"
TEE_TYPE="${TEE_TYPE:-}"
USER="${USER:-$(id -u)}"
GID="${GID:-$(id -g)}"

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
runtime_src_path="${katacontainers_repo_dir}/src/runtime"
agent_ctl_path="${katacontainers_repo_dir}/src/tools/agent-ctl"
runtime_rs_src_path="${katacontainers_repo_dir}/src/runtime-rs"

PKGDEFAULTSDIR="${DESTDIR}${SHAREDIR}/defaults/kata-containers"
NEW_RUNTIME_CONFIG="${PKGDEFAULTSDIR}/configuration.toml"
# Note: This will also install the config file.

clone_katacontainers_repo

build_install_shim_v2(){
	if [ "$KATA_BUILD_CC" == "yes" ]; then
		build_static_artifact_and_install "shim-v2"

		local bin_dir="/usr/bin"
		if [ "$PREFIX" != "$bin_dir" ]; then
			for target_file in $PREFIX/bin/*; do
				sudo ln --force -s "$target_file" "$bin_dir"
			done
		fi
		return
	fi

	build_static_artifact_and_install "shim-v2"

	sudo ln --force -s ${PREFIX}/bin/containerd-shim-kata-v2 /usr/local/bin/
	sudo ln --force -s ${PREFIX}/bin/kata-monitor /usr/local/bin/
	sudo ln --force -s ${PREFIX}/bin/kata-runtime /usr/local/bin/
	sudo ln --force -s ${PREFIX}/bin/kata-collect-data.sh /usr/local/bin/main
	if [ "$KATA_HYPERVISOR" == "dragonball" ]; then
		sudo ln --force -s ${PREFIX}/runtime-rs/bin/containerd-shim-kata-v2 /usr/local/bin/
	fi
}

build_install_shim_v2

build_install_agent_ctl(){
	bash "${cidir}/install_rust.sh" && source "$HOME/.cargo/env"
	pushd "$agent_ctl_path"
	sudo chown -R "${USER}:${GID}" "${katacontainers_repo_dir}"
	make
	make install
	popd
}

if [ "${KATA_BUILD_CC}" == "no" ]; then
	build_install_agent_ctl
fi

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
	sudo ln -sf "${path}" "${PKGDEFAULTSDIR}/configuration.toml"
}

case "${KATA_HYPERVISOR}" in
	"acrn")
		enable_hypervisor_config "${PKGDEFAULTSDIR}/configuration-acrn.toml"
		;;
	"cloud-hypervisor")
		if [ "$TEE_TYPE" == "tdx" ]; then
			enable_hypervisor_config "${PKGDEFAULTSDIR}/configuration-clh-tdx.toml"
		else
			enable_hypervisor_config "${PKGDEFAULTSDIR}/configuration-clh.toml"
		fi
		;;
	"firecracker")
		enable_hypervisor_config "${PKGDEFAULTSDIR}/configuration-fc.toml"
		;;
	"qemu")
		if [ "$TEE_TYPE" == "tdx" ]; then
			enable_hypervisor_config "${PKGDEFAULTSDIR}/configuration-qemu-tdx.toml"
		elif [ "$TEE_TYPE" == "sev" ]; then
			enable_hypervisor_config "${PKGDEFAULTSDIR}/configuration-qemu-sev.toml"
		elif [ "$TEE_TYPE" == "se" ]; then
			enable_hypervisor_config "${PKGDEFAULTSDIR}/configuration-qemu-se.toml"
		else
			enable_hypervisor_config "${PKGDEFAULTSDIR}/configuration-qemu.toml"
		fi

		if [ "$arch" == "x86_64" ]; then
			# Due to a KVM bug, vmx-rdseed-exit must be disabled in QEMU >= 4.2
			# All CI now uses qemu 5.0+, disabled in the time..
			# see https://github.com/kata-containers/runtime/pull/2355#issuecomment-625469252
			sudo sed -i --follow-symlinks 's|^cpu_features="|cpu_features="-vmx-rdseed-exit,|g' "${runtime_config_path}"
		fi
		;;
	"dragonball")
		enable_hypervisor_config "${PKGDEFAULTSDIR}/configuration-dragonball.toml"
		;;
	*)
		die "failed to enable config for '${KATA_HYPERVISOR}', not supported"
		;;
esac

if [ x"${TEST_INITRD}" == x"yes" ]; then
	echo "Set to test initrd image"
	image_path="${image_path:-$SHAREDIR/kata-containers}"
	initrd_name=${initrd_name:-kata-containers-initrd.img}
	sudo sed -i --follow-symlinks -e "s|^image =.*|initrd = \"$image_path/$initrd_name\"|" "${runtime_config_path}"
fi

if [ -z "${METRICS_CI}" ]; then
	echo "Enabling all debug options in file ${runtime_config_path}"
	sudo sed -i --follow-symlinks -e 's/^#\(enable_debug\).*=.*$/\1 = true/g' "${runtime_config_path}"
	sudo sed -i --follow-symlinks -e 's/^kernel_params = "\(.*\)"/kernel_params = "\1 agent.log=debug"/g' "${runtime_config_path}"
else
	echo "Metrics run - do not enable all debug options in file ${runtime_config_path}"
fi

if [ "$USE_VSOCK" == "yes" ]; then
	echo "Configure use of VSOCK in ${runtime_config_path}"
	sudo sed -i --follow-symlinks -e 's/^#use_vsock.*/use_vsock = true/' "${runtime_config_path}"

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
	sudo sed -i --follow-symlinks -e 's|machine_type = "pc"|machine_type = "q35"|' "${runtime_config_path}"
fi

# Enable experimental features if KATA_EXPERIMENTAL_FEATURES is set to true
if [ "$KATA_EXPERIMENTAL_FEATURES" = true ]; then
	echo "Enable runtime experimental features"
	feature="newstore"
	sudo sed -i --follow-symlinks -e "s|^experimental.*$|experimental=[ \"$feature\" ]|" "${runtime_config_path}"
fi

# Enable virtio-blk device driver only for ubuntu with initrd for this moment
# see https://github.com/kata-containers/tests/issues/1603
if [ "$ID" == ubuntu ] && [ x"${TEST_INITRD}" == x"yes" ] && [ "$VERSION_ID" != "16.04" ] && [ "$arch" != "ppc64le" ]; then
	echo "Set virtio-blk as the block device driver on $ID"
	sudo sed -i --follow-symlinks 's/block_device_driver = "virtio-scsi"/block_device_driver = "virtio-blk"/' "${runtime_config_path}"
fi

