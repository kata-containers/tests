#!/bin/bash
#
# Copyright (c) 2021 ARM Limited
#
# SPDX-License-Identifier: Apache-2.0

set -e

source /etc/os-release || source /usr/lib/os-release

EDK2_REPO="https://github.com/tianocore/edk2.git"
EDK2_PLAT_REPO="https://github.com/tianocore/edk2-platforms.git"
ACPICA="https://github.com/acpica/acpica.git"

#build toolchain
TOOLCHAIN_VERSION="10.2-2020.11"
TOOLCHAIN_ARCHIVE_PREFIX="gcc-arm-${TOOLCHAIN_VERSION}-aarch64-aarch64-none-elf"
TOOLCHAIN_ARCHIVE="${TOOLCHAIN_ARCHIVE_PREFIX}.tar.xz"
TOOLCHAIN_PREFIX="${TOOLCHAIN_ARCHIVE_PREFIX}/bin/aarch64-none-elf-"
TOOLCHAIN_SOURCE_URL="https://developer.arm.com/-/media/Files/downloads/gnu-a/${TOOLCHAIN_VERSION}/binrel/${TOOLCHAIN_ARCHIVE}"

export WORKSPACE=$(mktemp -d)

QEMU_EFI_BUILD_PATH="${WORKSPACE}/Build/ArmVirtQemu-AARCH64/RELEASE_GCC5/FV/QEMU_EFI.fd"

PREFIX="${PREFIX:-/usr}"
INSTALL_PATH="${DESTDIR:-}${PREFIX}/share/kata-containers"

EFI_NAME="QEMU_EFI.fd"
EFI_DEFAULT_DIR="/usr/share/qemu-efi-aarch64"
EFI_DEFAULT_PATH="${EFI_DEFAULT_DIR}/${EFI_NAME}"

FLASH0_NAME="kata-flash0.img"
FLASH1_NAME="kata-flash1.img"

HOW_TO_CROSS_BUILD="https://developer.arm.com/tools-and-software/open-source-software/firmware/edkii-uefi-firmware/building-edkii-uefi-firmware-for-arm-platforms"

arch=$(uname -m)

build_uefi()
{
	pushd "${WORKSPACE}"
	git clone "${EDK2_REPO}"
	git clone "${EDK2_PLAT_REPO}"
	git clone "${ACPICA}"


	sudo apt install -y python python3 python3-distutils uuid-dev build-essential bison flex

	mkdir toolchain
	pushd toolchain/
	curl -LO "${TOOLCHAIN_SOURCE_URL}" && tar -xf "${TOOLCHAIN_ARCHIVE}"
	popd

	make -C acpica/

	export GCC5_AARCH64_PREFIX="${WORKSPACE}/toolchain/${TOOLCHAIN_PREFIX}"
	export PACKAGES_PATH=$WORKSPACE/edk2:$WORKSPACE/edk2-platforms
	export IASL_PREFIX=$WORKSPACE/acpica/generate/unix/bin/

	export PYTHON_COMMAND=/usr/bin/python3

	git -C edk2/ submodule update --init
	source edk2/edksetup.sh
	make -C edk2/BaseTools

	build -a AARCH64 -t GCC5 -p edk2/ArmVirtPkg/ArmVirtQemu.dsc -b RELEASE
	echo "Info: build uefi successfully"

	popd
}

prepare_default_uefi()
{
	if [ "$ID" == "ubuntu" ] || [ "$ID" == "debian" ]; then
		sudo apt remove -y qemu-efi-aarch64
		sudo apt install -y qemu-efi-aarch64
	else
		local efi_url="https://releases.linaro.org/components/kernel/uefi-linaro/latest/release/qemu64/QEMU_EFI.fd"
		sudo mkdir -p "${EFI_DEFAULT_DIR}"
		pushd "${WORKSPACE}" || clean_up_and_die "fail to prepare default uefi."
		curl -LO ${efi_url}
		sudo install -o root -g root -m 644 QEMU_EFI.fd ${EFI_DEFAULT_DIR}
		popd
	fi
}

prepare_uefi_flash() {
	pushd "${WORKSPACE}"

	dd if=/dev/zero of=${FLASH0_NAME} bs=1M count=64
	dd if="$1" of=${FLASH0_NAME} conv=notrunc
	dd if=/dev/zero of=${FLASH1_NAME} bs=1M count=64

	popd
}

install_uefi_flash()
{
	[ -z "$1" -o -z "$2" ] && clean_up_and_die "fail to install uefi flash for lack of input"
	[ -d "${INSTALL_PATH}" ] || mkdir -p ${INSTALL_PATH}
	sudo install --mode 0544 -D "$1" "${INSTALL_PATH}/${FLASH0_NAME}"
	sudo install --mode 0544 -D "$2" "${INSTALL_PATH}/${FLASH1_NAME}"
}

clean_up_and_die()
{
	clean_up
	echo "ERROR: $*" >&2
	exit 1
}

clean_up()
{
	sudo rm -rf "${WORKSPACE}"
}

main()
{
	[ $(id -u) == 0 ] && echo "run this script as root"

	# If you want to build the latest uefi from source code (and it is recommended)
	# please run this script in ubuntu:18.04+ on arm64 machine or cross build then copy
	# the rom images to your arm64 machine.
	if [ "${arch}" != "aarch64" ]; then
		echo "Please find solution at ${HOW_TO_CROSS_BUILD}"
		exit 0
	fi

	if [ "$ID" == "ubuntu" -a `echo "${VERSION_ID} > 18" | bc` -eq 1 ]; then
		build_uefi
		prepare_uefi_flash "${QEMU_EFI_BUILD_PATH}"
		install_uefi_flash "${WORKSPACE}/${FLASH0_NAME}" "${WORKSPACE}/${FLASH1_NAME}"
	else
		prepare_default_uefi
		if [ -e  "${EFI_DEFAULT_PATH}" ]; then
			prepare_uefi_flash "${EFI_DEFAULT_PATH}"
			install_uefi_flash "${WORKSPACE}/${FLASH0_NAME}" "${WORKSPACE}/${FLASH1_NAME}"
		else
			clean_up_and_die "fail to install uefi flash image on arm64"
		fi
	fi

	echo "Info: install uefi rom image successfully"
	clean_up
}

main
