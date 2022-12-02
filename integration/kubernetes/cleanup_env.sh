#!/bin/bash
#
# Copyright (c) 2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#
# This script is used to reset the kubernetes cluster

SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_PATH}/../../.ci/lib.sh"
source "${SCRIPT_PATH}/../../lib/common.bash"

BAREMETAL="${BAREMETAL:-false}"
CRI_RUNTIME="${CRI_RUNTIME:-crio}"

main () {
	local cri_runtime_socket=""
	local keep_cni_bin="${1:-false}"

	case "${CRI_RUNTIME}" in
	containerd)
		cri_runtime_socket="/run/containerd/containerd.sock"
		;;
	crio)
		cri_runtime_socket="/var/run/crio/crio.sock"
		;;
	*)
		die "Runtime ${CRI_RUNTIME} not supported"
		;;
	esac

	info "Reset Kubernetes"
	export KUBECONFIG="$HOME/.kube/config"
	sudo -E kubeadm reset -f --cri-socket="${cri_runtime_socket}"

	info "Teardown the registry server"
	[ "${container_engine}" == "docker" ] && restart_docker_service
	registry_server_teardown

	info "Stop ${CRI_RUNTIME} service"
	sudo systemctl stop "${CRI_RUNTIME}"

	info "Remove network devices"
	for dev in cni0 flannel.1; do
		info "remove device: $dev"
		sudo ip link set dev "$dev" down || true
		sudo ip link del "$dev" || true
	done

	# if CI run in bare-metal, we need a set of extra clean
	if [ "${BAREMETAL}" == true ] && [ -f "${SCRIPT_PATH}/cleanup_bare_metal_env.sh" ]; then
		bash -f "${SCRIPT_PATH}/cleanup_bare_metal_env.sh ${keep_cni_bin}"
	fi

	info "Check no kata processes are left behind after reseting kubernetes"
	check_processes

	info "Checks that pods were not left"
	check_pods
}

main $@
