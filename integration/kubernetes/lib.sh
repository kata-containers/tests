#!/usr/bin/env bash
# Copyright 2023 Advanced Micro Devices, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#

TESTS_REPO_DIR=$(realpath $(dirname "${BASH_SOURCE[0]}")/../..)
FIXTURES_DIR="${TESTS_REPO_DIR}/integration/kubernetes/confidential/fixtures"

# Generate kubernetes service yaml from template
k8s_generate_service_yaml() {
  local service_yaml="${1}"
  local image="${2}"

  # Extract name from the file name
  local name=$(basename "${service_yaml%.*}")

  local service_yaml_template="${FIXTURES_DIR}/service.yaml.in"
  
  NAME="${name}" IMAGE="${image}" RUNTIMECLASS="${RUNTIMECLASS}" \
    envsubst < "${service_yaml_template}" > "${service_yaml}"
}

# Set annotation for yaml
k8s_yaml_set_annotation() {
  local yaml="${1}"
  local key="${2}"
  local value="${3}"
 
  # yaml annotation key name
  local annotation_key="spec.template.metadata.annotations.\"${key}\""
  
  # yq set annotations in yaml
  "${GOPATH}/bin/yq" w -i --style=double -d1 "${yaml}" "${annotation_key}" "${value}"
}

# Wait until the pod is 'Ready'. Fail if it hits the timeout.
k8s_wait_for_pod_ready_state() {
  local pod_name="${1}"
  local wait_time="${2:-10}"

  kubectl wait --for=condition=ready "pod/${pod_name}" --timeout=${wait_time}s
}

# Wait until the pod is 'Deleted'. Fail if it hits the timeout.
k8s_wait_for_pod_delete_state() {
  local pod_name="${1}"
  local wait_time="${2:-10}"

  kubectl wait --for=delete "pod/${pod_name}" --timeout=${wait_time}s
}

# Find container id
k8s_get_container_id() {
  local pod_name="${1}"

  # Get container id from pod info
  local container_id=$(kubectl get pod "${pod_name}" \
    -o jsonpath='{.status.containerStatuses..containerID}' \
    | sed "s|containerd://||g")

  echo "${container_id}"
}

# Delete k8s entity by yaml
k8s_delete_by_yaml() {
  local partial_pod_name="${1}"
  local yaml="${2}"

  # Retrieve pod name
  local pod_name=$(kubectl get pod -o wide | grep ${partial_pod_name} | awk '{print $1;}' || true)

  # Delete by yaml
  kubectl delete -f "${yaml}" 2>/dev/null || true
  
  # Verify pod deleted
  [ -z "${pod_name}" ] || (k8s_wait_for_pod_delete_state "${pod_name}" || true)
}

# Retrieve pod name and log kubernetes environment information: 
# nodes, services, deployments, pods
k8s_print_info() {
  local partial_pod_name="${1}"
  
  echo "-------------------------------------------------------------------------------"
  kubectl get nodes -o wide
  echo "-------------------------------------------------------------------------------"
  kubectl get services -o wide
  echo "-------------------------------------------------------------------------------"
  kubectl get deployments -o wide
  echo "-------------------------------------------------------------------------------"
  kubectl get pods -o wide
  echo "-------------------------------------------------------------------------------"
  local pod_name=$(kubectl get pod -o wide | grep "${partial_pod_name}" | awk '{print $1;}')
  kubectl describe pod "${pod_name}"
  echo "-------------------------------------------------------------------------------"
}
