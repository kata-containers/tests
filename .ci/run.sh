#!/bin/bash
#
# Copyright (c) 2017-2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

# This script will execute the Kata Containers Test Suite.

set -e

cidir=$(dirname "$0")
source "${cidir}/lib.sh"

export RUNTIME="kata-runtime"

export CI_JOB="${CI_JOB:-default}"

case "${CI_JOB}" in
	"CRI_CONTAINERD_K8S")
		echo "INFO: Containerd checks"
		sudo -E PATH="$PATH" bash -c "make cri-containerd"
		sudo -E PATH="$PATH" CRI_RUNTIME="containerd" bash -c "make kubernetes"

		# Make sure the feature works with K8s + containerd
		"${cidir}/toggle_sandbox_cgroup_only.sh" true
		sudo -E PATH="$PATH" bash -c "make cri-containerd"
		"${cidir}/toggle_sandbox_cgroup_only.sh" true
		sudo -E PATH="$PATH" CRI_RUNTIME="containerd" bash -c "make kubernetes"
		# remove config created by toggle_sandbox_cgroup_only.sh
		"${cidir}/toggle_sandbox_cgroup_only.sh" false
		sudo rm -f "/etc/kata-containers/configuration.toml"

		echo "INFO: Running docker integration tests with sandbox cgroup enabled"
		sudo -E PATH="$PATH" bash -c "make sandbox-cgroup"
		;;
	"FIRECRACKER")
		echo "INFO: Running docker integration tests"
		sudo -E PATH="$PATH" bash -c "make docker"
		echo "INFO: Running soak test"
		sudo -E PATH="$PATH" bash -c "make docker-stability"
		echo "INFO: Running oci call test"
		sudo -E PATH="$PATH" bash -c "make oci"
		echo "INFO: Running networking tests"
		sudo -E PATH="$PATH" bash -c "make network"
		echo "INFO: Running crio tests"
		sudo -E PATH="$PATH" bash -c "make crio"
		;;
	"CLOUD-HYPERVISOR")
		echo "INFO: Running soak test"
		sudo -E PATH="$PATH" bash -c "make docker-stability"

		echo "INFO: Running oci call test"
		sudo -E PATH="$PATH" bash -c "make oci"

		echo "INFO: Running networking tests"
		sudo -E PATH="$PATH" bash -c "make network"
		;;
	"CLOUD-HYPERVISOR-DOCKER")
		echo "INFO: Running docker integration tests"
		sudo -E PATH="$PATH" bash -c "make docker"
		;;
	"CLOUD-HYPERVISOR-PODMAN")
		export TRUSTED_GROUP="kvm"
		newgrp "${TRUSTED_GROUP}" << END
		echo "This is running as group $(id -gn)"
END
		echo "INFO: Running podman integration tests"
		bash -c "make podman"
		;;
	"CLOUD-HYPERVISOR-K8S-CONTAINERD")
		echo "INFO: Containerd checks"
		sudo -E PATH="$PATH" bash -c "make cri-containerd"

		echo "INFO: Running kubernetes tests with containerd"
		sudo -E PATH="$PATH" bash -c "make kubernetes"
		;;
	"CLOUD-HYPERVISOR-K8S-CRIO")
		echo "INFO: Running crio tests"
		sudo -E PATH="$PATH" bash -c "make crio"

		echo "INFO: Running kubernetes tests with cri-o"
		sudo -E PATH="$PATH" bash -c "make kubernetes"
		;;
	"CLOUD-HYPERVISOR-K8S-E2E-CRIO-MINIMAL")
		sudo -E PATH="$PATH" bash -c "make kubernetes-e2e"
		;;
	"CLOUD-HYPERVISOR-K8S-E2E-CONTAINERD-MINIMAL")
		sudo -E PATH="$PATH" bash -c "make kubernetes-e2e"
		;;
	"CLOUD-HYPERVISOR-K8S-E2E-CRIO-FULL")
		sudo -E PATH="$PATH" bash -c "make kubernetes-e2e"
		;;
	"CLOUD-HYPERVISOR-K8S-E2E-CONTAINERD-FULL")
		sudo -E PATH="$PATH" bash -c "make kubernetes-e2e"
		;;
	"PODMAN")
		export TRUSTED_GROUP="kvm"
		newgrp "${TRUSTED_GROUP}" << END
		echo "This is running as group $(id -gn)"
END
		echo "INFO: Running podman integration tests"
		bash -c "make podman"
		;;
	"RUST_AGENT")
		echo "INFO: Running docker integration tests"
		sudo -E PATH="$PATH" bash -c "make docker"
		echo "INFO: Running soak test"
		sudo -E PATH="$PATH" bash -c "make docker-stability"
		echo "INFO: Running kubernetes tests"
		sudo -E PATH="$PATH" bash -c "make kubernetes"
		;;
	"VFIO")
		echo "INFO: Running VFIO functional tests"
		sudo -E PATH="$PATH" bash -c "make vfio"
		;;
	"SNAP")
		echo "INFO: Running docker tests ($PWD)"
		sudo -E PATH="$PATH" bash -c "make docker"

		echo "INFO: Running crio tests ($PWD)"
		sudo -E PATH="$PATH" bash -c "make crio"

		echo "INFO: Running kubernetes tests ($PWD)"
		sudo -E PATH="$PATH" bash -c "make kubernetes"

		echo "INFO: Running shimv2 tests ($PWD)"
		sudo -E PATH="$PATH" bash -c "make shimv2"
		;;
	*)
		echo "INFO: Running checks"
		sudo -E PATH="$PATH" bash -c "make check"

		echo "INFO: Running functional and integration tests ($PWD)"
		sudo -E PATH="$PATH" bash -c "make test"
		;;
esac
