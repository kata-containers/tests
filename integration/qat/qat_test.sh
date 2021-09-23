#!/bin/bash
#
# Copyright (c) 2021 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#
# WARNING: This script only support Intel® QAT c6xx devices
#

set -x
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

dir_path=$(dirname "$0")
source "${dir_path}/../../lib/common.bash"
source "${dir_path}/../../.ci/lib.sh"
source /etc/os-release || source /usr/lib/os-release
arch=$("${dir_path}"/../../.ci/kata-arch.sh -d)

QAT_DRIVER_VER=qat1.7.l.4.14.0-00031.tar.gz
QAT_DRIVER_URL=https://downloadmirror.intel.com/30178/eng/${QAT_DRIVER_VER}
# List of QAT device IDs
QAT_VENDOR_AND_ID_VF=
QAT_DEVICE_ID=37c8
QAT_VENDOR_ID=8086
QAT_DEV_ADDR=
SSL_IMAGE_TAG=openssl-qat-engine
CTR_RUNTIME="${CTR_RUNTIME:-io.containerd.run.kata.v2}"

if [ "${arch}" == "aarch64" ] || [ "${arch}" == "s390x" ] || [ "${arch}" == "ppc64le" ]; then
	echo "Skip QAT test: $arch doesn't support QAT"
	exit 0
fi

if [ "${ID}" != "ubuntu" ]; then
	echo "Skip QAT test: ${ID} distro is not supported"
	exit 0
fi

init() {
	local qat_devices=$(lspci -d ${QAT_VENDOR_ID}:${QAT_DEVICE_ID})
	[ -n "${qat_devices}" ] || die "This system doesn't have any QAT device"
	sudo modprobe vfio
	sudo modprobe vfio-pci
}

build_install_qat_image_and_kernel() {
	local osbuilder_dir="${GOPATH}/src/github.com/kata-containers/kata-containers/tools/osbuilder/dockerfiles/QAT"
	local kata_vmlinux_path="/usr/share/kata-containers/vmlinux.container"
	local config_file="/usr/share/defaults/kata-containers/configuration.toml"
	local kata_image_path="/usr/share/kata-containers/kata-containers.img"

	pushd "${osbuilder_dir}"
	sudo rm -rf output && mkdir -p output
	sudo docker rmi -f kataqat
	sudo docker build --rm --label kataqat --tag kataqat:latest .
	sudo docker run -i --rm --privileged -e "QAT_DRIVER_VER=${QAT_DRIVER_VER}" -e "QAT_DRIVER_URL=${QAT_DRIVER_URL}" -v /dev:/dev -v ${PWD}/output:/output  kataqat

	sudo rm -f ${kata_vmlinux_path} ${kata_image_path}

	sudo cp -a output/vmlinux-* ${kata_vmlinux_path}
	sudo cp -a output/kata-containers.img ${kata_image_path}

	sudo sed -i -e 's/^kernel_params = "\(.*\)"/kernel_params = "\1 modules-load=usdm_drv,qat_c62xvf"/g' ${config_file}
	popd
}

build_openssl_image() {
	local openssl_tar="openssl-qat-engine.tar"
	local docker_openssl_img="docker.io/library/${SSL_IMAGE_TAG}:latest"
	pushd ${dir_path}
	curl -LOk https://raw.githubusercontent.com/intel/intel-device-plugins-for-kubernetes/main/demo/openssl-qat-engine/Dockerfile
	sudo docker build --rm -t ${SSL_IMAGE_TAG} .
	sudo docker save -o ${openssl_tar} ${SSL_IMAGE_TAG}:latest
	sudo ctr i rm ${docker_openssl_img} || true
	sudo ctr images import ${openssl_tar}
	sudo rm -f ${openssl_tar}
	popd
}

bind_vfio_dev() {
	QAT_DEV_ADDR="0000:$(lspci -n -d ${QAT_VENDOR_ID}:${QAT_DEVICE_ID} | cut -d' ' -f1 | head -1)"
	echo 16 | sudo tee -a /sys/bus/pci/devices/${QAT_DEV_ADDR}/sriov_numvfs
	local qat_pci_id_vf=$(cat /sys/bus/pci/devices/${QAT_DEV_ADDR}/virtfn0/uevent | grep PCI_ID)
	QAT_VENDOR_AND_ID_VF=$(echo ${qat_pci_id_vf/PCI_ID=} | sed 's/:/ /')

	echo ${QAT_VENDOR_AND_ID_VF} | sudo tee -a /sys/bus/pci/drivers/vfio-pci/new_id
	for f in /sys/bus/pci/devices/${QAT_DEV_ADDR}/virtfn*;	do
		local qat_pci_bus_vf=$(basename $(readlink $f))
		echo ${qat_pci_bus_vf} | sudo tee -a /sys/bus/pci/drivers/c6xxvf/unbind
		echo ${qat_pci_bus_vf} | sudo tee -a /sys/bus/pci/drivers/vfio-pci/bind
	done
}

unbind_pci_device() {
	for f in /sys/bus/pci/devices/${QAT_DEV_ADDR}/virtfn*;  do
		local qat_pci_bus_vf=$(basename $(readlink $f))
		echo ${qat_pci_bus_vf} | sudo tee -a /sys/bus/pci/drivers/vfio-pci/unbind
		echo ${qat_pci_bus_vf} | sudo tee -a /sys/bus/pci/drivers/c6xxvf/bind
	done
	echo ${QAT_VENDOR_AND_ID_VF} | sudo tee -a /sys/bus/pci/drivers/vfio-pci/remove_id
}

cleanup() {
	[ -z "${QAT_DEV_ADDR}" ] || unbind_pci_device
	clean_env_ctr
}

run_test() {
	local docker_ssl_img="docker.io/library/openssl-qat-engine:latest"
	local vfio_dev=$(ls /dev/vfio/ | head -1)
	local qat_conf_dir="${GOPATH}/src/github.com/kata-containers/kata-containers/tools/osbuilder/dockerfiles/QAT/output/configs"
	local config_file="/usr/share/defaults/kata-containers/configuration.toml"

	sudo sed -i -e 's/^kernel_params =.*/kernel_params = "modules-load=usdm_drv,qat_c62xvf"/g' ${config_file}

	sudo ctr run --runtime ${CTR_RUNTIME} --privileged -d -t --rm --device=/dev/vfio/${vfio_dev} \
		 --mount type=bind,src=/dev,dst=/dev,options=rbind:rw \
		 --mount type=bind,src=${qat_conf_dir}/c6xxvf_dev0.conf,dst=/etc/c6xxvf_dev0.conf,options=rbind:rw \
		 ${docker_ssl_img} qat /bin/bash

	sudo ctr t exec --exec-id 2 qat cat /proc/modules | grep intel_qat
	sudo ctr t exec --exec-id 2 qat adf_ctl restart 2>/dev/null || true
	sudo ctr t exec --exec-id 2 qat adf_ctl status | grep "qat_dev0" | grep "c6xxvf" | grep "state: up"
	local ssl_output=$(sudo ctr t exec --exec-id 2 qat openssl engine -c -t qat-hw)
	echo "${ssl_output}" | grep "qat-hw"
	echo "${ssl_output}" | grep "\[ available \]"
	sudo sed -i -e 's/^kernel_params =.*/kernel_params = ""/g' ${config_file}
}

main() {
	trap cleanup EXIT QUIT KILL
	init
	build_install_qat_image_and_kernel
	build_openssl_image
	bind_vfio_dev
	run_test
}

main
