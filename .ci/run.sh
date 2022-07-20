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
source "/etc/os-release" || source "/usr/lib/os-release"

export RUNTIME="containerd-shim-kata-v2"

export CI_JOB="${CI_JOB:-default}"

# Kata *MUST BE* able to run using a read-only rootfs image
if [ "$(uname -m)" == "x86_64" ]; then
	rootfs_img="$(grep "^image = " \
	/usr/share/defaults/kata-containers/configuration.toml \
	/etc/kata-containers/configuration.toml 2> /dev/null \
	| cut -d= -f2 | tr -d '"' | tr -d ' ' || true)"
	if [ -n "${rootfs_img}" ] && [ -w "${rootfs_img}" ]; then
		echo "INFO: making rootfs image read-only"
		sudo mount --bind -r "${rootfs_img}" "${rootfs_img}"
	fi
fi

case "${CI_JOB}" in
	"BAREMETAL-PMEM"|"PMEM")
		echo "INFO: Running pmem integration test"
		sudo -E PATH="$PATH" CRI_RUNTIME="containerd" bash -c "make pmem"
		;;
	"BAREMETAL-QAT"|"QAT")
		echo "INFO: Running QAT integration test"
		sudo -E PATH="$PATH" CRI_RUNTIME="containerd" bash -c "make qat"
		;;
	"CRI_CONTAINERD"|"CRI_CONTAINERD_K8S"|"CRI_CONTAINERD_K8S_DEVMAPPER")
		echo "INFO: Skipping nydus test: Issue: https://github.com/kata-containers/tests/issues/4947"
		#echo "INFO: Running nydus test"
		#sudo -E PATH="$PATH" CRI_RUNTIME="containerd" bash -c "make nydus"
		echo "INFO: Running stability test"
		sudo -E PATH="$PATH" CRI_RUNTIME="containerd" bash -c "make stability"
		echo "INFO: Containerd checks"
		sudo -E PATH="$PATH" bash -c "make cri-containerd"
		[[ "${CI_JOB}" =~ K8S ]] && \
			sudo -E PATH="$PATH" CRI_RUNTIME="containerd" bash -c "make kubernetes"
		echo "INFO: Running vcpus test"
		sudo -E PATH="$PATH" CRI_RUNTIME="containerd" bash -c "make vcpus"
		echo "INFO: Skipping pmem test: Issue: https://github.com/kata-containers/tests/issues/3223"
		if [ "${NAME}" == "Ubuntu" ] && [ "$(echo "${VERSION_ID} >= 22.04" | bc -q)" == "1" ]; then
			issue="https://github.com/kata-containers/tests/issues/4922"
			echo "INFO: Skipping stability test with sandbox_cgroup_only as they are not working with cgroupsv2 see $issue"
		else
			echo "INFO: Running stability test with sandbox_cgroup_only"
			export TEST_SANDBOX_CGROUP_ONLY=true
			sudo -E PATH="$PATH" CRI_RUNTIME="containerd" bash -c "make stability"
		fi
		# echo "INFO: Running pmem integration test"
		# sudo -E PATH="$PATH" CRI_RUNTIME="containerd" bash -c "make pmem"
		echo "INFO: Running ksm test"
		sudo -E PATH="$PATH" CRI_RUNTIME="containerd" bash -c "make ksm"
		echo "INFO: Running kata-monitor test"
		sudo -E PATH="$PATH" CRI_RUNTIME="containerd" bash -c "make monitor"
		echo "INFO: Running tracing test"
		sudo -E PATH="$PATH" bash -c "make tracing"
		
		# TODO - one issue #4755 is resolved we can uncomment these and run the CC tests at the end of the run job.
		# if [[ "${CI_JOB}" =~ CC_CRI_CONTAINERD ]] || [[ "${CI_JOB}" =~ CC_SKOPEO_CRI_CONTAINERD ]]; then
		# 	echo "INFO: Running Confidential Container tests"
		# 	sudo -E PATH="$PATH" CRI_RUNTIME="containerd" bash -c "make cc-containerd"
		# fi
		;;
	"CC_CRI_CONTAINERD"|"CC_SKOPEO_CRI_CONTAINERD"|"CC_CRI_CONTAINERD_CLOUD_HYPERVISOR"|"CC_SKOPEO_CRI_CONTAINERD_CLOUD_HYPERVISOR")
		echo "INFO: Running Confidential Container tests"
		sudo -E PATH="$PATH" CRI_RUNTIME="containerd" bash -c "make cc-containerd"
		;;
	"CC_CRI_CONTAINERD_K8S"|"CC_SKOPEO_CRI_CONTAINERD_K8S")
		info "Running Confidential Container tests"
		sudo -E PATH="$PATH" CRI_RUNTIME="containerd" bash -c "make cc-kubernetes"
		;;
	"CRIO_K8S")
		echo "INFO: Running kubernetes tests"
		sudo -E PATH="$PATH" bash -c "make kubernetes"
		echo "INFO: Running rootless tests"
		sudo -E PATH="$PATH" bash -c "make rootless"
		echo "INFO: Running kata-monitor test"
		sudo -E PATH="$PATH" bash -c "make monitor"
		;;
	"CRIO_K8S_COMPLETE")
		echo "INFO: Running kubernetes tests (minimal) with CRI-O"
		sudo -E PATH="$PATH" bash -c "make kubernetes-e2e"
		;;
	"CRIO_K8S_MINIMAL")
		echo "INFO: Running kubernetes tests (minimal) with CRI-O"
		sudo -E PATH="$PATH" bash -c "make kubernetes-e2e"
		;;
	"CLOUD-HYPERVISOR-K8S-CRIO")
		echo "INFO: Running kubernetes tests"
		sudo -E PATH="$PATH" bash -c "make kubernetes"
		;;
	"CLOUD-HYPERVISOR-K8S-CONTAINERD"|"CLOUD-HYPERVISOR-K8S-CONTAINERD-DEVMAPPER")
		echo "INFO: Containerd checks"
		sudo -E PATH="$PATH" bash -c "make cri-containerd"

		echo "INFO: Running kubernetes tests with containerd"
		sudo -E PATH="$PATH" CRI_RUNTIME="containerd" bash -c "make kubernetes"
		;;
	"EXTERNAL_CLOUD_HYPERVISOR")
		echo "INFO:n Running tests on Cloud Hypervisor PR"
		sudo -E PATH="$PATH" bash -c "make cri-containerd"
		;;
	"EXTERNAL_CRIO")
		echo "INFO: Running tests on cri-o PR"
		sudo -E PATH="$PATH" bash -c "make kubernetes"
		sudo -E PATH="$PATH" bash -c "make kubernetes-e2e"
		sudo -E PATH="$PATH" bash -c "make crio"
		;;
	"FIRECRACKER")
		echo "INFO: Running Kubernetes tests with Jailed Firecracker"
		sudo -E PATH="$PATH" bash -c "make kubernetes"
		;;
	"VFIO")
		echo "INFO: Running VFIO functional tests"
		sudo -E PATH="$PATH" CRI_RUNTIME="containerd" bash -c "make vfio"
		;;
	"METRICS")
		export RUNTIME="kata-runtime"
		export CTR_RUNTIME="io.containerd.kata.v2"
		export config_path="/usr/share/defaults/kata-containers"
		tests_repo="github.com/kata-containers/tests"

		echo "INFO: Running qemu metrics tests"
		export KATA_HYPERVISOR="qemu"
		sudo -E ln -sf "${config_path}/configuration-qemu.toml" "${config_path}/configuration.toml"
		sudo -E PATH="$PATH" ".ci/run_metrics_PR_ci.sh"

		echo "INFO: Install cloud hypervisor"
		export KATA_HYPERVISOR="cloud-hypervisor"
		pushd "${GOPATH}/src/${tests_repo}"
		sudo -E PATH="$PATH" ".ci/install_cloud_hypervisor.sh"
		popd

		echo "INFO: Use cloud hypervisor configuration"
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