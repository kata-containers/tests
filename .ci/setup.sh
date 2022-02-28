#!/bin/bash
#
# Copyright (c) 2017-2020 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail

cidir=$(dirname "$0")
source /etc/os-release || source /usr/lib/os-release
source "${cidir}/lib.sh"

arch=$("${cidir}"/kata-arch.sh -d)
INSTALL_KATA="${INSTALL_KATA:-yes}"
CI=${CI:-false}

# values indicating whether related intergration tests have been supported
CRIO="${CRIO:-yes}"
CRI_CONTAINERD="${CRI_CONTAINERD:-no}"
KATA_HYPERVISOR="${KATA_HYPERVISOR:-qemu}"
KUBERNETES="${KUBERNETES:-yes}"
TEST_CGROUPSV2="${TEST_CGROUPSV2:-false}"

setup_distro_env() {
	local setup_type="$1"
	[ -z "$setup_type" ] && die "need setup type"

	local script

	echo "Set up environment ($setup_type)"

	if [[ "$ID" =~ ^opensuse.*$ ]]; then
		script="${cidir}/setup_env_opensuse.sh"
	else
		script="${cidir}/setup_env_${ID}.sh"
	fi

	[ -n "$script" ] || die "Failed to determine distro setup script"
	[ -e "$script" ] || die "Unrecognised distribution: ${ID}"

	bash -f "${script}" "${setup_type}"

	sudo systemctl start haveged
}

install_container_engine() {
	if [ "${TEST_CGROUPSV2}" == "true" ]; then
		info "Docker won't be installed: testing cgroups V2"
		return
	fi

	if [ "${USE_PODMAN:-}" == "true" ]; then
		# Podman is the primary container engine on Fedora-likes
		# Remove Docker repo to avoid its runc, see https://github.com/containers/podman/issues/8764
		sudo rm -f /etc/yum.repos.d/docker-ce.repo
		# if crun is installed, remove it (it will also remove podman if it's the only runtime)
		command -v crun && sudo dnf remove -y crun
		# Then install runc from the distribution repo so that podman will use it
		sudo dnf install -y runc
		# Try reinstalling to fix CNI configuration, allow erasing incompatible containerd
		sudo dnf reinstall -y podman || sudo dnf install -y --allowerasing podman
		# Install docker-podman, so scripts from outside our repo which are not aware of podman don't break
		sudo dnf -y install podman-docker
		return
	fi

	if ! command -v docker >/dev/null; then
		"${cidir}/../cmd/container-manager/manage_ctr_mgr.sh" docker install
	fi

	restart_docker_service
}

enable_nested_virtualization() {
	case "$arch" in
	x86_64 | s390x)
		kvm_arch="kvm"
		[ ${arch} == "x86_64" ] && kvm_arch="kvm_intel"
		if [ "$CI" == true ] && grep -q "N" /sys/module/$kvm_arch/parameters/nested 2>/dev/null; then
			echo "enable Nested Virtualization"
			sudo modprobe -r $kvm_arch
			sudo modprobe $kvm_arch nested=1
			if grep -q "N" /sys/module/$kvm_arch/parameters/nested 2>/dev/null; then
				die "Failed to find or enable Nested virtualization"
			fi
		fi
		;;
	aarch64 | ppc64le)
		info "CI running in bare machine"
		;;
	*)
		die "Unsupported architecture: $arch"
		;;
	esac
}

install_kata() {
	if [ "${INSTALL_KATA}" == "yes" ]; then
		echo "Install Kata sources"
		bash -f ${cidir}/install_kata.sh
	fi
}

install_extra_tools() {
	echo "Install CNI plugins"
	bash -f "${cidir}/install_cni_plugins.sh"

	# Remove K8s + CRIO conf that may remain from a previous run
	sudo rm -f /etc/systemd/system/kubelet.service.d/0-crio.conf

	if [ "${CRIO}" == "yes" ]; then
		info "Install CRI-O"
		bash -f "${cidir}/install_crio.sh"
		bash -f "${cidir}/configure_crio_for_kata.sh"
	fi

	if [ "${CRI_CONTAINERD}" == "yes" ]; then
		info "Install cri-containerd"
		bash -f "${cidir}/install_cri_containerd.sh"
		bash -f "${cidir}/configure_containerd_for_kata.sh"
	fi

	if [ "${KATA_HYPERVISOR}" == "firecracker" ]; then
		info "Configure devicemapper for firecracker"
		bash -f "${cidir}/containerd_devmapper_setup.sh"
	fi

	if [ "${KUBERNETES}" == "yes" ]; then
		info "Install Kubernetes"
		bash -f "${cidir}/install_kubernetes.sh"
		if [ "${CRI_CONTAINERD}" == "yes" ]; then
			bash -f "${cidir}/configure_containerd_for_kubernetes.sh"
		fi
	fi

}

main() {
	local setup_type="default"

	# Travis only needs a very basic setup
	set +o nounset
	[ "$TRAVIS" = "true" ] && setup_type="minimal"
	set -o nounset

	[ "$setup_type" = "default" ] && bash -f "${cidir}/install_go.sh" -p -f

	setup_distro_env "$setup_type"

	[ "$setup_type" = "minimal" ] && info "finished minimal setup" && exit 0

	print_environment
	if [ "$arch" == "s390x" ] && ([ "$ID" == "fedora" ] || [[ "${ID_LIKE:-}" =~ "fedora" ]]); then
		# see https://github.com/kata-containers/osbuilder/issues/217
		export CC=gcc
	fi

	install_container_engine
	enable_nested_virtualization
	install_kata
	install_extra_tools
	echo "Disable systemd-journald rate limit"
	sudo crudini --set /etc/systemd/journald.conf Journal RateLimitInterval 0s
	sudo crudini --set /etc/systemd/journald.conf Journal RateLimitBurst 0
	sudo systemctl restart systemd-journald

	echo "Drop caches"
	sync
	sudo -E PATH=$PATH bash -c "echo 3 > /proc/sys/vm/drop_caches"
}

main $*
