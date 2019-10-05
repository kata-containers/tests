#!/bin/bash
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

RUNTIMECLASS=${RUNTIMECLASS:-kata}
MEM_IN_MB=${MEM_IN_MB:-2048}
CPUS=${CPUS:-4}

sed -e "s,@CPUS@,${CPUS},g" \
	-e "s,@MEM_IN_MB@,${MEM_IN_MB},g" \
	-e "s,@RUNTIMECLASS@,${RUNTIMECLASS},g" \
	workloads.yaml.in > workloads.yaml

kubectl create -f workloads.yaml

if ! kubectl wait pod -l app="overhead" --for=condition=Ready --timeout "300s"; then
	echo "Timeout to get pods in ready"
	kubectl describe pod -l app="overhead"
	exit 1
fi

echo "pods are running"
echo
