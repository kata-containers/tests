#!/bin/bash
#
# Copyright (c) 2020 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

# Entry point to start a K8S cluster for end-to-end testing
# If cluster is already running with Kata RuntimeClass, skip this script and
# use run.sh

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_PATH}/../../../lib/common.bash"
source "${SCRIPT_PATH}/../../../.ci/lib.sh"
CRI_RUNTIME="${CRI_RUNTIME:-containerd}"

wait_init_retry="10s"

info "Setup env for K8s e2e testing"
cd "${GOPATH}/src/github.com/kata-containers/tests/integration/kubernetes"
if ! bash ./init.sh; then
	info "k8s init failed trying again"
	bash ./cleanup_env.sh
	sleep "${wait_init_retry}"
	bash ./init.sh
fi
crictl --version
kubectl get runtimeclass
kubectl apply -f "runtimeclass_workloads/kata-runtimeclass.yaml"
kubectl get pods --all-namespaces
