#!/bin/bash
#
# Copyright (c) 2017-2020 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

# This script will execute the Kata Containers Test Suite.

set -e

cidir=$(dirname "$0")
source "${cidir}/lib.sh"

export RUNTIME="containerd-shim-kata-v2"

export CI_JOB="${CI_JOB:-default}"

case "${CI_JOB}" in
	"CRI_CONTAINERD_K8S")
		echo "INFO: Running stability test"
		sudo -E PATH="$PATH" CRI_RUNTIME="containerd" bash -c "make stability"
		echo "INFO: Containerd checks"
		sudo -E PATH="$PATH" bash -c "make cri-containerd"
		sudo -E PATH="$PATH" CRI_RUNTIME="containerd" bash -c "make kubernetes"
		echo "INFO: Running vcpus test"
		sudo -E PATH="$PATH" CRI_RUNTIME="containerd" bash -c "make vcpus"
		echo "INFO: Skipping pmem test: Issue: https://github.com/kata-containers/tests/issues/3223"
		echo "INFO: Running stability test with sandbox_cgroup_only"
		export TEST_SANDBOX_CGROUP_ONLY=true
		sudo -E PATH="$PATH" CRI_RUNTIME="containerd" bash -c "make stability"
		# echo "INFO: Running pmem integration test"
		# sudo -E PATH="$PATH" CRI_RUNTIME="containerd" bash -c "make pmem"
		;;
	"CRI_CONTAINERD_K8S_COMPLETE")
		echo "INFO: Running e2e kubernetes tests"
		sudo -E PATH="$PATH" CRI_RUNTIME="containerd" bash -c "make kubernetes-e2e"
		;;
	"CRI_CONTAINERD_K8S_MINIMAL")
		echo "INFO: Running e2e kubernetes tests"
		sudo -E PATH="$PATH" CRI_RUNTIME="containerd" bash -c "make kubernetes-e2e"
		;;
	"CRIO_K8S")
		echo "INFO: Running kubernetes tests"
		sudo -E PATH="$PATH" bash -c "make kubernetes"
		;;
	"CRIO_K8S_MINIMAL")
		echo "INFO: Running kubernetes tests (minimal) with CRI-O"
		sudo -E PATH="$PATH" bash -c "make kubernetes-e2e"
		;;
	"CLOUD-HYPERVISOR-K8S-CRIO")
		echo "INFO: Running kubernetes tests"
		sudo -E PATH="$PATH" bash -c "make kubernetes"
		;;
	"CLOUD-HYPERVISOR-K8S-CONTAINERD")
		echo "INFO: Containerd checks"
		sudo -E PATH="$PATH" bash -c "make cri-containerd"

		echo "INFO: Running kubernetes tests with containerd"
		sudo -E PATH="$PATH" CRI_RUNTIME="containerd" bash -c "make kubernetes"
		;;
	"CLOUD-HYPERVISOR-K8S-CONTAINERD-MINIMAL")
		echo "INFO: Running e2e kubernetes tests"
		sudo -E PATH="$PATH" CRI_RUNTIME="containerd" bash -c "make kubernetes-e2e"
		;;
	"CLOUD-HYPERVISOR-K8S-CONTAINERD-FULL")
		echo "INFO: Running complete e2e kubernetes tests"
		sudo -E PATH="$PATH" CRI_RUNTIME="containerd" bash -c "make kubernetes-e2e"
		;;
	"FIRECRACKER")
		echo "INFO: Running Kubernetes tests with Firecracker"
		sudo -E PATH="$PATH" bash -c "make kubernetes"
		;;
	"VFIO")
		echo "INFO: Running VFIO functional tests"
		sudo -E PATH="$PATH" CRI_RUNTIME="containerd" bash -c "make vfio"
		;;
	"METRICS")
		export RUNTIME="kata-runtime"
		export CTR_RUNTIME="io.containerd.run.kata.v2"
		sudo -E ln -sf "${config_path}/configuration-qemu.toml" "${config_path}/configuration.toml"
		echo "INFO: Running qemu metrics tests"
		sudo -E PATH="$PATH" ".ci/run_metrics_PR_ci.sh"
		echo "INFO: Running cloud hypervisor metrics tests"
		export KATA_HYPERVISOR="cloud-hypervisor"
		tests_repo="github.com/kata-containers/tests"
		pushd "${GOPATH}/src/${tests_repo}"
		echo "INFO: Install cloud hypervisor"
		sudo -E PATH="$PATH" ".ci/install_cloud_hypervisor.sh"
		popd
		echo "INFO: Use cloud hypervisor configuration"
		export config_path="/usr/share/defaults/kata-containers"
		sudo -E ln -sf "${config_path}/configuration-clh.toml" "${config_path}/configuration.toml"
		echo "INFO: Running cloud hypervisor metrics tests"
		sudo -E PATH="$PATH" ".ci/run_metrics_PR_ci.sh"
		;;
	"VIRTIOFS_EXPERIMENTAL")
		sudo -E PATH="$PATH" bash -c "make filesystem"
		;;
	*)
		echo "INFO: Running checks"
		sudo -E PATH="$PATH" bash -c "make check"

		echo "INFO: Running functional and integration tests ($PWD)"
		sudo -E PATH="$PATH" bash -c "make test"
		;;
esac
