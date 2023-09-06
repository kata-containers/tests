#!/usr/bin/env bats
# Copyright 2023 Advanced Micro Devices, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#

# Environment variables
TEST_TAG="[cc][kubernetes][containerd][snp]"
TESTS_REPO_DIR=$(realpath "${BATS_TEST_DIRNAME}/../../..")
RUNTIMECLASS="${RUNTIMECLASS:-"kata"}"
IMAGE_REPO="ghcr.io/confidential-containers/test-container"
UNENCRYPTED_IMAGE_URL="${IMAGE_REPO}:unencrypted"

# Text to grep for active feature in guest dmesg output
SNP_DMESG_GREP_TEXT="Memory Encryption Features active:.*SEV-SNP"

export TEST_DIR
export ENCRYPTION_KEY
export SSH_KEY_FILE

load "${BATS_TEST_DIRNAME}/../../confidential/lib.sh"
load "${TESTS_REPO_DIR}/lib/common.bash"
load "${TESTS_REPO_DIR}/integration/kubernetes/lib.sh"
load "${BATS_TEST_DIRNAME}/tests_common.sh"

# Delete all test services
k8s_delete_all() {
	kubernetes_delete_by_yaml "snp-unencrypted" "${TEST_DIR}/snp-unencrypted.yaml"
}

setup_file() {
  TEST_DIR="$(mktemp -d /tmp/test-kata-snp.XXXXXXXX)"
  SSH_KEY_FILE="${TEST_DIR}/container-ssh-key"

  # Install package dependencies
  echo "Installing required packages..."
  esudo apt install -y jq

  # Configure CoCo settings in containerd config
  local saved_containerd_conf_file="/etc/containerd/config.toml.$$"
  configure_cc_containerd "${saved_containerd_conf_file}"
  restart_containerd

  # Pull unencrypted image and retrieve ssh keys
  echo "Pulling unencrypted image and retrieve ssh key..."
  docker_image_label_save_ssh_key "${UNENCRYPTED_IMAGE_URL}" "${SSH_KEY_FILE}"

  # SEV service yaml generation
  kubernetes_generate_service_yaml "${TEST_DIR}/snp-unencrypted.yaml" "${IMAGE_REPO}:unencrypted"
}

teardown_file() {
  # Allow to not destroy the environment if you are developing/debugging tests
  if [[ "${CI:-false}" == "false" && "${DEBUG:-}" == true ]]; then
    echo "Leaving changes and created resources untouched"
    return
  fi

  # Remove all k8s test services
  k8s_delete_all

  # Cleanup directories
  esudo rm -rf "${TEST_DIR}"
}

setup() {
  # Remove any previous k8s test services
  echo "Deleting previous test services..."
  k8s_delete_all
}


@test "${TEST_TAG} Test SNP unencrypted container launch success" {
  # Start the service/deployment/pod
  esudo kubectl apply -f "${TEST_DIR}/snp-unencrypted.yaml"
  
  # Retrieve pod name, wait for it to come up, retrieve pod ip
  local pod_name=$(esudo kubectl get pod -o wide | grep snp-unencrypted | awk '{print $1;}')
  kubernetes_wait_for_pod_ready_state "$pod_name" 20
  local pod_ip=$(esudo kubectl get pod -o wide | grep snp-unencrypted | awk '{print $6;}')

  kubernetes_print_info "snp-unencrypted"

  # Look for SEV enabled in container dmesg output
  local snp_enabled=$(ssh_dmesg_grep \
    "${SSH_KEY_FILE}" \
    "${pod_ip}" \
    "${SNP_DMESG_GREP_TEXT}")

  if [ -z "${snp_enabled}" ]; then
    >&2 echo -e "KATA SNP TEST - FAIL: SNP is NOT Enabled"
    return 1
  else
    echo "DMESG REPORT: ${snp_enabled}"
    echo -e "KATA SNP TEST - PASS: SNP is Enabled"
  fi
}
