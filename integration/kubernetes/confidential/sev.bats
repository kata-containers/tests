#!/usr/bin/env bats
# Copyright 2022-2023 Advanced Micro Devices, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#

# Environment variables
TEST_TAG="[cc][kubernetes][containerd][sev]"
TESTS_REPO_DIR=$(realpath "${BATS_TEST_DIRNAME}/../../..")
SIMPLE_KBS_DIR="${SIMPLE_KBS_DIR:-/tmp/simple-kbs}"
RUNTIMECLASS="${RUNTIMECLASS:-"kata"}"
SEV_CONFIG_FILE="/opt/confidential-containers/share/defaults/kata-containers/configuration-qemu-sev.toml"
IMAGE_REPO="ghcr.io/confidential-containers/test-container"
UNENCRYPTED_IMAGE_URL="${IMAGE_REPO}:unencrypted"

# Text to grep for active feature in guest dmesg output
SEV_DMESG_GREP_TEXT="Memory Encryption Features active:.*\(SEV$\|SEV \)"
SEV_ES_DMESG_GREP_TEXT="Memory Encryption Features active:.*SEV-ES"

export TEST_DIR
export ENCRYPTION_KEY
export SSH_KEY_FILE

load "${BATS_TEST_DIRNAME}/../../confidential/lib.sh"
load "${TESTS_REPO_DIR}/lib/common.bash"
load "${TESTS_REPO_DIR}/integration/kubernetes/lib.sh"
load "${TESTS_REPO_DIR}/integration/kubernetes/confidential/lib.sh"

# Delete all test services
k8s_delete_all() {
  for file in $(ls "${TEST_DIR}/*.yaml") ; do
    # Removing extension to get the pod name
    local pod_name="${file%.*}"
    kubernetes_delete_by_yaml "${pod_name}" "${TEST_DIR}/${file}"
  done
}


setup_file() {
  TEST_DIR="$(mktemp -d /tmp/test-kata-sev.XXXXXXXX)"
  SSH_KEY_FILE="${TEST_DIR}/container-ssh-key"

  # Install package dependencies
  echo "Installing required packages..."
  esudo apt install -y \
    python-is-python3 \
    python3-pip \
    jq \
    mysql-client \
    docker-compose \
    cpuid
  pip install sev-snp-measure
  "${TESTS_REPO_DIR}/.ci/install_yq.sh" >&2

  # Configure CoCo settings in containerd config
  local saved_containerd_conf_file="/etc/containerd/config.toml.$$"
  configure_cc_containerd "${saved_containerd_conf_file}"

  # KBS setup and run
  echo "Setting up simple-kbs..."
  simple_kbs_run

  # Pull unencrypted image and retrieve encryption and ssh keys
  echo "Pulling unencrypted image and retrieving keys..."
  ENCRYPTION_KEY=$(docker_image_label_get_encryption_key "${UNENCRYPTED_IMAGE_URL}")
  docker_image_label_save_ssh_key "${UNENCRYPTED_IMAGE_URL}" "${SSH_KEY_FILE}"

  # Get host ip and set as simple-kbs ip; uri uses default port 44444
  # These values will be set as k8s annotations in the service yamls
  local kbs_ip="$(ip -o route get to 8.8.8.8 | sed -n 's/.*src \([0-9.]\+\).*/\1/p')"
  local kbs_uri="${kbs_ip}:44444"

  # SEV unencrypted service yaml generation
  kubernetes_generate_service_yaml "${TEST_DIR}/sev-unencrypted.yaml" "${IMAGE_REPO}:unencrypted"
  kubernetes_yaml_set_annotation "${TEST_DIR}/sev-unencrypted.yaml" "io.katacontainers.config.guest_pre_attestation.enabled" "false"

  # SEV encrypted service yaml generation
  # SEV policy is 3 (default):
  # - NODBG (1): Debugging of the guest is disallowed when set
  # - NOKS (2): Sharing keys with other guests is disallowed when set
  kubernetes_generate_service_yaml "${TEST_DIR}/sev-encrypted.yaml" "${IMAGE_REPO}:multi-arch-encrypted"
  kubernetes_yaml_set_annotation "${TEST_DIR}/sev-encrypted.yaml" "io.katacontainers.config.pre_attestation.uri" "${kbs_uri}"
  kubernetes_yaml_set_annotation "${TEST_DIR}/sev-encrypted.yaml" "io.katacontainers.config.sev.policy" "3"
  
  # SEV-ES policy is 7:
  # - NODBG (1): Debugging of the guest is disallowed when set
  # - NOKS (2): Sharing keys with other guests is disallowed when set
  # - ES (4): SEV-ES is required when set
  kubernetes_generate_service_yaml "${TEST_DIR}/sev-es-encrypted.yaml" "${IMAGE_REPO}:multi-arch-encrypted"
  kubernetes_yaml_set_annotation "${TEST_DIR}/sev-es-encrypted.yaml" "io.katacontainers.config.pre_attestation.uri" "${kbs_uri}"
  kubernetes_yaml_set_annotation "${TEST_DIR}/sev-es-encrypted.yaml" "io.katacontainers.config.sev.policy" "7"
}

teardown_file() {
  # Allow to not destroy the environment if you are developing/debugging tests
  if [[ "${CI:-false}" == "false" && "${DEBUG:-}" == true ]]; then
    echo "Leaving changes and created resources untouched"
    return
  fi

  # Remove all k8s test services
  k8s_delete_all

  # Stop the simple-kbs
  simple_kbs_stop

  # Cleanup directories
  esudo rm -rf "${SIMPLE_KBS_DIR}"
  esudo rm -rf "${TEST_DIR}"
}

setup() {
  start_date=$(date +"%Y-%m-%d %H:%M:%S")
  # Remove any previous k8s test services
  echo "Deleting previous test services..."
  k8s_delete_all

  # Delete any previous data in the simple-kbs database
  simple_kbs_delete_data
}

teardown() {
  # Print the logs and cleanup resources.
  echo "-- Kata logs:"
  sudo journalctl -xe -t kata --since "$start_date" -n 100000
}

@test "${TEST_TAG} Test SEV unencrypted container launch success" {  
  # Start the service/deployment/pod
  esudo kubectl apply -f "${TEST_DIR}/sev-unencrypted.yaml"
  
  # Retrieve pod name, wait for it to come up, retrieve pod ip
  local pod_name=$(esudo kubectl get pod -o wide | grep sev-unencrypted | awk '{print $1;}')
  kubernetes_wait_for_pod_ready_state "$pod_name" 20
  local pod_ip=$(esudo kubectl get pod -o wide | grep sev-unencrypted | awk '{print $6;}')

  kubernetes_print_info "sev-unencrypted"

  # Look for SEV enabled in container dmesg output
  local sev_enabled=$(ssh_dmesg_grep \
    "${SSH_KEY_FILE}" \
    "${pod_ip}" \
    "${SEV_DMESG_GREP_TEXT}")

  if [ -z "${sev_enabled}" ]; then
    >&2 echo -e "KATA SEV TEST - FAIL: SEV is NOT Enabled"
    return 1
  else
    echo "DMESG REPORT: ${sev_enabled}"
    echo -e "KATA SEV TEST - PASS: SEV is Enabled"
  fi
}

@test "${TEST_TAG} Test SEV encrypted container launch failure with INVALID measurement" {
  # Generate firmware measurement
  local append="INVALID-INPUT"
  local measurement=$(generate_firmware_measurement_with_append "${SEV_CONFIG_FILE}" "${append}")
  echo "Firmware Measurement: ${measurement}"

  # Add key to KBS with policy measurement
  simple_kbs_add_key_to_db "${ENCRYPTION_KEY}" "${measurement}"
  
  # Start the service/deployment/pod
  esudo kubectl apply -f "${TEST_DIR}/sev-encrypted.yaml"
  
  # Retrieve pod name, wait for it to fail
  local pod_name=$(esudo kubectl get pod -o wide | grep sev-encrypted | awk '{print $1;}')
  kubernetes_wait_for_pod_ready_state "$pod_name" 20 || true

  kubernetes_print_info "sev-encrypted"

  # Save guest qemu kernel append to file
  local kernel_append=$(kata_get_guest_kernel_append "${pod_name}")
  echo "${kernel_append}" > "${TEST_DIR}/guest-kernel-append"
  echo "Kernel Append Retrieved from QEMU Process: ${kernel_append}"

  # Get pod info
  local pod_info=$(esudo kubectl describe pod ${pod_name})

  # Check failure condition
  if [[ ! ${pod_info} =~ "Failed to pull image" ]]; then
    >&2 echo -e "TEST - FAIL"
    return 1
  else
    echo "Pod message contains: Failed to pull image"
    echo -e "TEST - PASS"
  fi
}

@test "${TEST_TAG} Test SEV encrypted container launch success with NO measurement" {
  # Add key to KBS without a policy measurement
  simple_kbs_add_key_to_db "${ENCRYPTION_KEY}"
  
  # Start the service/deployment/pod
  esudo kubectl apply -f "${TEST_DIR}/sev-encrypted.yaml"

  # Retrieve pod name, wait for it to come up, retrieve pod ip
  local pod_name=$(esudo kubectl get pod -o wide | grep sev-encrypted | awk '{print $1;}')
  kubernetes_wait_for_pod_ready_state "$pod_name" 20
  local pod_ip=$(esudo kubectl get pod -o wide | grep sev-encrypted | awk '{print $6;}')

  kubernetes_print_info "sev-encrypted"

  # Look for SEV enabled in container dmesg output
  local sev_enabled=$(ssh_dmesg_grep \
    "${SSH_KEY_FILE}" \
    "${pod_ip}" \
    "${SEV_DMESG_GREP_TEXT}")

  if [ -z "${sev_enabled}" ]; then
    >&2 echo -e "KATA SEV TEST - FAIL: SEV is NOT Enabled"
    return 1
  else
    echo "DMESG REPORT: ${sev_enabled}"
    echo -e "KATA SEV TEST - PASS: SEV is Enabled"
  fi
}

@test "${TEST_TAG} Test SEV encrypted container launch success with VALID measurement" {
  # Generate firmware measurement
  local append=$(cat ${TEST_DIR}/guest-kernel-append)
  echo "Kernel Append: ${append}"
  local measurement=$(generate_firmware_measurement_with_append "${SEV_CONFIG_FILE}" "${append}")
  echo "Firmware Measurement: ${measurement}"

  # Add key to KBS with policy measurement
  simple_kbs_add_key_to_db "${ENCRYPTION_KEY}" "${measurement}"
  
  # Start the service/deployment/pod
  esudo kubectl apply -f "${TEST_DIR}/sev-encrypted.yaml"

  # Retrieve pod name, wait for it to come up, retrieve pod ip
  local pod_name=$(esudo kubectl get pod -o wide | grep sev-encrypted | awk '{print $1;}')
  kubernetes_wait_for_pod_ready_state "$pod_name" 20
  local pod_ip=$(esudo kubectl get pod -o wide | grep sev-encrypted | awk '{print $6;}')

  kubernetes_print_info "sev-encrypted"

  # Look for SEV enabled in container dmesg output
  local sev_enabled=$(ssh_dmesg_grep \
    "${SSH_KEY_FILE}" \
    "${pod_ip}" \
    "${SEV_DMESG_GREP_TEXT}")

  if [ -z "${sev_enabled}" ]; then
    >&2 echo -e "KATA SEV TEST - FAIL: SEV is NOT Enabled"
    return 1
  else
    echo "DMESG REPORT: ${sev_enabled}"
    echo -e "KATA SEV TEST - PASS: SEV is Enabled"
  fi
}

@test "${TEST_TAG} Test SEV-ES encrypted container launch success with VALID measurement" {
  # Generate firmware measurement
  local append=$(cat ${TEST_DIR}/guest-kernel-append)
  echo "Kernel Append: ${append}"
  local measurement=$(generate_firmware_measurement_with_append "${SEV_CONFIG_FILE}" "${append}" "seves")
  echo "Firmware Measurement: ${measurement}"

  # Add key to KBS with policy measurement
  simple_kbs_add_key_to_db "${ENCRYPTION_KEY}" "${measurement}"
  
  # Start the service/deployment/pod
  esudo kubectl apply -f "${TEST_DIR}/sev-es-encrypted.yaml"

  # Retrieve pod name, wait for it to come up, retrieve pod ip
  local pod_name=$(esudo kubectl get pod -o wide | grep sev-es-encrypted | awk '{print $1;}')
  kubernetes_wait_for_pod_ready_state "$pod_name" 20
  local pod_ip=$(esudo kubectl get pod -o wide | grep sev-es-encrypted | awk '{print $6;}')

  kubernetes_print_info "sev-es-encrypted"

  # Look for SEV-ES enabled in container dmesg output
  local sev_es_enabled=$(ssh_dmesg_grep \
    "${SSH_KEY_FILE}" \
    "${pod_ip}" \
    "${SEV_ES_DMESG_GREP_TEXT}")

  if [ -z "${sev_es_enabled}" ]; then
    >&2 echo -e "KATA SEV-ES TEST - FAIL: SEV-ES is NOT Enabled"
    return 1
  else
    echo "DMESG REPORT: ${sev_es_enabled}"
    echo -e "KATA SEV-ES TEST - PASS: SEV-ES is Enabled"
  fi
}
