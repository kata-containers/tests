#!/usr/bin/env bats
# Copyright 2022 Advanced Micro Devices, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#

load "${BATS_TEST_DIRNAME}/../../confidential/lib.sh"

export TEST_DIR
export ENCRYPTION_KEY
export SSH_KEY_FILE

export KBS_DIR
export KBS_DB_HOST
export KBS_DB_USER="kbsuser"
export KBS_DB_PW="kbspassword"
export KBS_DB="simple_kbs"
export KBS_DB_TYPE="mysql"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

TESTS_REPO_DIR=$(realpath "$BATS_TEST_DIRNAME/../../..")
load "${TESTS_REPO_DIR}/lib/common.bash"
#load "${TESTS_REPO_DIR}/.ci/lib.sh"
test_tag="[cc][kubernetes][containerd][sev]"

export SEV_CONFIG="/opt/confidential-containers/share/defaults/kata-containers/configuration-qemu-sev.toml"
export RUNTIMECLASS=${RUNTIMECLASS:-"kata"}
export FIXTURES_DIR="${TESTS_REPO_DIR}/integration/kubernetes/confidential/fixtures"
export IMAGE_REPO="ghcr.io/confidential-containers/test-container"

esudo() {
  sudo -E PATH=$PATH "$@"
}

get_version() {
  local dependency="${1}"
  local versions_file="${TESTS_REPO_DIR}/versions.yaml"

  # Error if versions file not present
  [ -f "${versions_file}" ] || (>&2 echo "Cannot find ${versions_file}"; return 1)

  # Install yq
  #"${TESTS_REPO_DIR}/.ci/install_yq.sh" >&2

  # Parse versions file with yq for dependency
  result=$("${GOPATH}/bin/yq" r -X "$versions_file" "$dependency")
  [ "$result" = "null" ] && result=""
  echo "$result"
}

generate_service_yaml() {
  local name="${1}"
  local image="${2}"

  # Default policy is 3:
  # - NODBG (1): Debugging of the guest is disallowed when set
  # - NOKS (2): Sharing keys with other guests is disallowed when set
  local policy="${3:-3}"

  local kbs_ip="$(ip -o route get to 8.8.8.8 | sed -n 's/.*src \([0-9.]\+\).*/\1/p')"
  local service_yaml_template="${FIXTURES_DIR}/service.yaml.in"

  local service_yaml="${TEST_DIR}/${name}.yaml"
  rm -f "${service_yaml}"
  
  NAME="${name}" IMAGE="${image}" RUNTIMECLASS="${RUNTIMECLASS}" \
    KBS_URI="${kbs_ip}:44444" \
    POLICY="$policy" \
    envsubst < "${service_yaml_template}" > "${service_yaml}"
}

# Wait until the pod is 'Ready'. Fail if it hits the timeout.
kubernetes_wait_for_pod_ready_state() {
  local pod_name="${1}"
  local wait_time="${2:-60}"

  esudo kubectl wait --for=condition=ready pod/$pod_name --timeout=${wait_time}s
}

# Wait until the pod is 'Deleted'. Fail if it hits the timeout.
kubernetes_wait_for_pod_delete_state() {
  local pod_name="${1}"
  local wait_time="${2:-60}"

  esudo kubectl wait --for=delete pod/$pod_name --timeout=${wait_time}s
}

# Find container id
get_container_id() {
  local pod_name="${1}"

  # Get container id from pod info
  local container_id=$(esudo kubectl get pod "${pod_name}" \
    -o jsonpath='{.status.containerStatuses..containerID}' \
    | sed "s|containerd://||g")

  echo "${container_id}"
}

# Find sandbox id using container ID
get_sandbox_id() {
  local container_id="${1}"
  local sandbox_dir="/run/kata-containers/shared/sandboxes"

  # Find container directory inside sandbox directory
  local container_dir=$(esudo find "${sandbox_dir}" -name "${container_id}" | head -1)

  # Ensure directory path pattern is correct
  [[ ${container_dir} =~ ^${sandbox_dir}/.*/.*/${container_id} ]] \
    || (>&2 echo "Incorrect container folder path: ${container_dir}"; return 1)

  # Two levels up, and trim the sandbox dir off the front
  local sandbox_id=$(dirname $(dirname "${container_dir}") | sed "s|${sandbox_dir}/||g")

  echo "${sandbox_id}"
}

# Get guest kernel append from qemu command line
get_guest_kernel_append() {
  local pod_name="${1}"
  local duration=$((SECONDS+20))
  local kernel_append

  # Attempt to get qemu command line from qemu process
  while [ $SECONDS -lt $duration ]; do
    container_id=$(get_container_id "${pod_name}")
    sandbox_id=$(get_sandbox_id "${container_id}")
    qemu_process=$(ps aux | grep qemu | grep ${sandbox_id} | grep append || true)
    if [ -n "${qemu_process}" ]; then
      kernel_append=$(echo ${qemu_process} \
        | sed "s|.*-append \(.*$\)|\1|g" \
        | sed "s| -.*$||")
      break
    fi
    sleep 1
  done

  [ -n "${kernel_append}" ] \
    || (>&2 echo "Could not retrieve guest kernel append parameters"; return 1)

  echo "${kernel_append}"
}

# Delete pods
delete_pods() {
  # Retrieve pod names
  local encrypted_pod_name=$(esudo kubectl get pod -o wide | grep encrypted-image-tests | awk '{print $1;}' || true)
  local unencrypted_pod_name=$(esudo kubectl get pod -o wide | grep unencrypted-image-tests | awk '{print $1;}' || true)
  local encrypted_pod_name_es=$(esudo kubectl get pod -o wide | grep encrypted-image-tests-es | awk '{print $1;}' || true)
  local signed_pod_name=$(esudo kubectl get pod -o wide | grep signed-image-tests | awk '{print $1;}' || true)
    local signed_pod_wrong_name=$(esudo kubectl get pod -o wide | grep signed-image-tests | awk '{print $1;}' || true)

  # Delete encrypted, unencrypted, and signed pods
  esudo kubectl delete -f \
    "${TEST_DIR}/unencrypted-image-tests.yaml" 2>/dev/null || true
  esudo kubectl delete -f \
    "${TEST_DIR}/encrypted-image-tests.yaml" 2>/dev/null || true
  esudo kubectl delete -f \
    "${TEST_DIR}/encrypted-image-tests-es.yaml" 2>/dev/null || true
  esudo kubectl delete -f \
    "${TEST_DIR}/signed-image-tests.yaml" 2>/dev/null || true
  esudo kubectl delete -f \
    "${TEST_DIR}/signed-image-wrong.yaml" 2>/dev/null || true

  [ -z "${encrypted_pod_name}" ] || (kubernetes_wait_for_pod_delete_state "${encrypted_pod_name}" || true)
  [ -z "${unencrypted_pod_name}" ] || (kubernetes_wait_for_pod_delete_state "${unencrypted_pod_name}" || true)
  [ -z "${encrypted_pod_name_es}" ] || (kubernetes_wait_for_pod_delete_state "${encrypted_pod_name_es}" || true)
  [ -z "${signed_pod_name}" ] || (kubernetes_wait_for_pod_delete_state "${signed_pod_name}" || true)
  [ -z "${signed_pod_wrong_name}" ] || (kubernetes_wait_for_pod_delete_state "${signed_pod_wrong_name}" || true)
}

run_kbs() {
  KBS_DIR="$(mktemp -d /tmp/kbs.XXXXXXXX)"
  pushd "${KBS_DIR}"

  # Retrieve simple-kbs repo and tag from versions.yaml
  local simple_kbs_url=$(get_version "externals.simple-kbs.url")
  local simple_kbs_tag=$(get_version "externals.simple-kbs.tag")

  # Clone and run
  git clone "${simple_kbs_url}" --branch main

  pushd simple-kbs
  git checkout -b "branch_${simple_kbs_tag}" "${simple_kbs_tag}"

  #copy resources
  mkdir -p resources/default/security-policy
  mkdir -p resources/default/cosign-public-key
  cp ${TESTS_REPO_DIR}/integration/kubernetes/confidential/fixtures/policy.json resources/default/security-policy/test
  cp ${TESTS_REPO_DIR}/integration/kubernetes/confidential/fixtures/cosign.pub resources/default/cosign-public-key/test
  
  esudo docker-compose build

  esudo docker-compose up -d
  until docker-compose top | grep -q "simple-kbs"
  do
    echo "waiting for simple-kbs to start"
    sleep 5
  done
  popd
  
  # Set KBS_DB_HOST to kbs db container IP
  KBS_DB_HOST=$(esudo docker network inspect simple-kbs_default \
    | jq -r '.[].Containers[] | select(.Name | test("simple-kbs[_-]db.*")).IPv4Address' \
    | sed "s|/.*$||g")

  waitForProcess 15 1 "mysql -u${KBS_DB_USER} -p${KBS_DB_PW} -h ${KBS_DB_HOST} -D ${KBS_DB} -e '\q'"
  popd
}

pull_unencrypted_image_and_set_keys() {
  # Pull unencrypted test image to get labels
  local unencrypted_image_url="${IMAGE_REPO}:unencrypted"
  esudo docker pull "${unencrypted_image_url}"

  # Get encryption key from docker image label
  ENCRYPTION_KEY=$(esudo docker inspect ${unencrypted_image_url} \
    | jq -r '.[0].Config.Labels.enc_key')

  # Get ssh key from docker image label and save to file
  esudo docker inspect ${unencrypted_image_url} \
    | jq -r '.[0].Config.Labels.ssh_key' \
    | sed "s|\(-----BEGIN OPENSSH PRIVATE KEY-----\)|\1\n|g" \
    | sed "s|\(-----END OPENSSH PRIVATE KEY-----\)|\n\1|g" \
    > "${SSH_KEY_FILE}"

  # Set permissions on private key file
  chmod 600 "${SSH_KEY_FILE}"
}

generate_firmware_measurement_with_append() {

  # Gather firmware locations and kernel append for measurement
  local append="${1}"
  local mode="${2:-sev}"
  local vcpu_sig=$(cpuid -1 --leaf 0x1 --raw | cut -s -f2 -d= | cut -f1 -d" ")
  local ovmf_path=$(grep "firmware = " $SEV_CONFIG | cut -d'"' -f2)
  local kernel_path="$(esudo /opt/confidential-containers/bin/kata-runtime \
    --config ${SEV_CONFIG} kata-env --json | jq -r .Kernel.Path)"
  local initrd_path="$(esudo /opt/confidential-containers/bin/kata-runtime \
    --config ${SEV_CONFIG} kata-env --json | jq -r .Initrd.Path)"
  
  # Return error if files don't exist
  [ -f "${ovmf_path}" ] || return 1
  [ -f "${kernel_path}" ] || return 1
  [ -f "${initrd_path}" ] || return 1

  # Generate digest from sev-snp-measure output - this also inserts measurement values inside OVMF image
  measurement=$(PATH="${PATH}:${HOME}/.local/bin" sev-snp-measure \
    --mode="${mode}" \
    --vcpus=1 \
    --vcpu-sig="${vcpu_sig}" \
    --output-format=base64 \
    --ovmf="${ovmf_path}" \
    --kernel="${kernel_path}" \
    --initrd="${initrd_path}" \
    --append="${append}" \
  )
  if [[ -z "${measurement}" ]]; then return 1; fi
  echo ${measurement}
}

add_key_to_kbs_db() {
  measurement=${1}

  # Add key and keyset to DB; If set, add policy with measurement to DB
  if [ -n "${measurement}" ]; then
    mysql -u${KBS_DB_USER} -p${KBS_DB_PW} -h ${KBS_DB_HOST} -D ${KBS_DB} <<EOF
      INSERT INTO secrets VALUES (10, 'default/key/ssh-demo', '${ENCRYPTION_KEY}', 10);
      INSERT INTO policy VALUES (10, '["${measurement}"]', '[]', 0, 0, '[]', now(), NULL, 1);
EOF
  else
    mysql -u${KBS_DB_USER} -p${KBS_DB_PW} -h ${KBS_DB_HOST} -D ${KBS_DB} <<EOF
      INSERT INTO secrets VALUES (10, 'default/key/ssh-demo', '${ENCRYPTION_KEY}', NULL);
EOF
  fi
}

print_service_info() {
  # Log kubectl environment information: nodes, services, deployments, pods
  # Retrieve pod name and IP
  echo "-------------------------------------------------------------------------------"
  esudo kubectl get nodes -o wide
  echo "-------------------------------------------------------------------------------"
  esudo kubectl get services -o wide
  echo "-------------------------------------------------------------------------------"
  esudo kubectl get deployments -o wide
  echo "-------------------------------------------------------------------------------"
  esudo kubectl get pods -o wide
  echo "-------------------------------------------------------------------------------"
  pod_name=$(esudo kubectl get pod -o wide | grep encrypted-image-tests | awk '{print $1;}')
  esudo kubectl describe pod ${pod_name}
  echo "-------------------------------------------------------------------------------"
}

setup_file() {
  echo "###############################################################################"
  echo -e "SETUP FILE - STARTED\n"

  start_date=$(date +"%Y-%m-%d %H:%M:%S")

  TEST_DIR="$(mktemp -d /tmp/test.XXXXXXXX)"
  SSH_KEY_FILE="${TEST_DIR}/encrypted-image-tests"

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

  SAVED_CONTAINERD_CONF_FILE="/etc/containerd/config.toml.$$"
  configure_cc_containerd "$SAVED_CONTAINERD_CONF_FILE"

  # KBS setup and run
  echo "Setting up simple-kbs..."
  run_kbs

  # Pull unencrypted image and retrieve encryption and ssh keys
  echo "Pulling unencrypted image and setting keys..."
  pull_unencrypted_image_and_set_keys

  generate_service_yaml "unencrypted-image-tests" "${IMAGE_REPO}:unencrypted"
  generate_service_yaml "encrypted-image-tests" "${IMAGE_REPO}:multi-arch-encrypted"
  generate_service_yaml "signed-image-tests" "quay.io/kata-containers/confidential-containers:cosign-signed"
  generate_service_yaml "signed-image-wrong" "quay.io/kata-containers/confidential-containers:cosign-signed-key2"

  # SEV-ES policy is 7:
  # - NODBG (1): Debugging of the guest is disallowed when set
  # - NOKS (2): Sharing keys with other guests is disallowed when set
  # - ES (4): SEV-ES is required when set
  generate_service_yaml "encrypted-image-tests-es" "${IMAGE_REPO}:multi-arch-encrypted" "7"

  echo "SETUP FILE - COMPLETE"
  echo "###############################################################################"
}

setup() {
  # Remove the service/deployment/pod if it exists
  echo "Deleting previous test pods..."
  delete_pods

  # Delete any previous data in the DB
  mysql -u${KBS_DB_USER} -p${KBS_DB_PW} -h ${KBS_DB_HOST} -D ${KBS_DB} <<EOF
    DELETE FROM secrets WHERE id = 10;
    DELETE FROM keysets WHERE id = 10;
    DELETE FROM policy WHERE id = 10;
    DELETE FROM resources WHERE id = 10;
EOF
}

setup_cosign_signatures_files() {
    measurement=${1}

    if [ -n "${measurement}" ]; then
        mysql -u${KBS_DB_USER} -p${KBS_DB_PW} -h ${KBS_DB_HOST} -D ${KBS_DB} <<EOF
        INSERT INTO resources SET resource_type="Policy", resource_path="default/security-policy/test", polid=10;
        INSERT INTO resources SET resource_type="Cosign Key", resource_path="default/cosign-public-key/test", polid=10;
        INSERT INTO policy VALUES (10, '["${measurement}"]', '[]', 0, 0, '[]', now(), NULL, 1);
EOF

    else
        mysql -u${KBS_DB_USER} -p${KBS_DB_PW} -h ${KBS_DB_HOST} -D ${KBS_DB} <<EOF
        INSERT INTO resources SET resource_type="Policy", resource_path="default/security-policy/test";
        INSERT INTO resources SET resource_type="Cosign Key", resource_path="default/cosign-public-key/test";
EOF
    fi
}

@test "$test_tag Test SEV unencrypted container launch success" {
  # Turn off pre-attestation. It is not necessary for an unencrypted image.
  esudo sed -i 's/guest_pre_attestation = true/guest_pre_attestation = false/g' ${SEV_CONFIG}
  
  # Turn off signature verification
  esudo sed -i 's/agent.enable_signature_verification=true/agent.enable_signature_verification=false/g' ${SEV_CONFIG}
  
  # Start the service/deployment/pod
  esudo kubectl apply -f "${TEST_DIR}/unencrypted-image-tests.yaml"
  
  # Retrieve pod name, wait for it to come up, retrieve pod ip
  pod_name=$(esudo kubectl get pod -o wide | grep unencrypted-image-tests | awk '{print $1;}')
  kubernetes_wait_for_pod_ready_state "$pod_name" 20
  pod_ip=$(esudo kubectl get pod -o wide | grep unencrypted-image-tests | awk '{print $6;}')

  print_service_info

  # Look for SEV enabled in container dmesg output
  sev_enabled=$(ssh -i ${SSH_KEY_FILE} \
    -o "StrictHostKeyChecking no" \
    -o "PasswordAuthentication=no" \
    -t root@${pod_ip} \
    'dmesg | grep SEV' || true)

  if [ -z "$sev_enabled" ]; then
    >&2 echo -e "${RED}KATA CC TEST - FAIL: SEV is NOT Enabled${NC}"
    return 1
  else
    echo "DMESG REPORT: $sev_enabled"
    echo -e "${GREEN}KATA CC TEST - PASS: SEV is Enabled${NC}"
  fi

}

@test "$test_tag Test SEV encrypted container launch failure with INVALID measurement" {
  # Make sure pre-attestation is enabled. 
  esudo sed -i 's/guest_pre_attestation = false/guest_pre_attestation = true/g' ${SEV_CONFIG}

  # Generate firmware measurement
  local append="INVALID-INPUT"
  measurement=$(generate_firmware_measurement_with_append ${append})
  echo "Firmware Measurement: ${measurement}"

  # Add key to KBS with policy measurement
  add_key_to_kbs_db ${measurement}
  
  # Start the service/deployment/pod
  esudo kubectl apply -f "${TEST_DIR}/encrypted-image-tests.yaml"
  
  # Retrieve pod name, wait for it to fail
  pod_name=$(esudo kubectl get pod -o wide | grep encrypted-image-tests | awk '{print $1;}')
  kubernetes_wait_for_pod_ready_state "$pod_name" 20 || true

  print_service_info

  # Save guest qemu kernel append to file
  kernel_append=$(get_guest_kernel_append "${pod_name}")
  echo "${kernel_append}" > "${TEST_DIR}/guest-kernel-append"
  echo "Kernel Append Retrieved from QEMU Process: ${kernel_append}"

  # Get pod info
  pod_info=$(esudo kubectl describe pod ${pod_name})

  # Check failure condition
  if [[ ! ${pod_info} =~ "Failed to pull image" ]]; then
    >&2 echo -e "${RED}TEST - FAIL${NC}"
    return 1
  else
    echo "Pod message contains: Failed to pull image"
    echo -e "${GREEN}TEST - PASS${NC}"
  fi
}

@test "$test_tag Test SEV encrypted container launch success with NO measurement" {

  # Add key to KBS without a policy measurement
  add_key_to_kbs_db
  
  # Start the service/deployment/pod
  esudo kubectl apply -f "${TEST_DIR}/encrypted-image-tests.yaml"

  # Retrieve pod name, wait for it to come up, retrieve pod ip
  pod_name=$(esudo kubectl get pod -o wide | grep encrypted-image-tests | awk '{print $1;}')
  kubernetes_wait_for_pod_ready_state "$pod_name" 20
  pod_ip=$(esudo kubectl get pod -o wide | grep encrypted-image-tests | awk '{print $6;}')

  print_service_info

  # Look for SEV enabled in container dmesg output
  sev_enabled=$(ssh -i ${SSH_KEY_FILE} \
    -o "StrictHostKeyChecking no" \
    -o "PasswordAuthentication=no" \
    -t root@${pod_ip} \
    'dmesg | grep SEV' || true)

  if [ -z "$sev_enabled" ]; then
    >&2 echo -e "${RED}KATA CC TEST - FAIL: SEV is NOT Enabled${NC}"
    return 1
  else
    echo "DMESG REPORT: $sev_enabled"
    echo -e "${GREEN}KATA CC TEST - PASS: SEV is Enabled${NC}"
  fi
}

@test "$test_tag Test SEV encrypted container launch success with VALID measurement" {

  # Generate firmware measurement
  local append=$(cat ${TEST_DIR}/guest-kernel-append)
  echo "Kernel Append: ${append}"
  measurement=$(generate_firmware_measurement_with_append "${append}")
  echo "Firmware Measurement: ${measurement}"

  # Add key to KBS with policy measurement
  add_key_to_kbs_db ${measurement}
  
  # Start the service/deployment/pod
  esudo kubectl apply -f "${TEST_DIR}/encrypted-image-tests.yaml"

  # Retrieve pod name, wait for it to come up, retrieve pod ip
  pod_name=$(esudo kubectl get pod -o wide | grep encrypted-image-tests | awk '{print $1;}')
  kubernetes_wait_for_pod_ready_state "$pod_name" 20
  pod_ip=$(esudo kubectl get pod -o wide | grep encrypted-image-tests | awk '{print $6;}')

  print_service_info

  # Look for SEV enabled in container dmesg output
  sev_enabled=$(ssh -i ${SSH_KEY_FILE} \
    -o "StrictHostKeyChecking no" \
    -o "PasswordAuthentication=no" \
    -t root@${pod_ip} \
    'dmesg | grep SEV' || true)

  if [ -z "$sev_enabled" ]; then
    >&2 echo -e "${RED}KATA CC TEST - FAIL: SEV is NOT Enabled${NC}"
    return 1
  else
    echo "DMESG REPORT: $sev_enabled"
    echo -e "${GREEN}KATA CC TEST - PASS: SEV is Enabled${NC}"
  fi
}

@test "$test_tag Test SEV-ES encrypted container launch success with VALID measurement" {

  # Generate firmware measurement
  local append=$(cat ${TEST_DIR}/guest-kernel-append)
  echo "Kernel Append: ${append}"
  measurement=$(generate_firmware_measurement_with_append "${append}" "seves")
  echo "Firmware Measurement: ${measurement}"

  # Add key to KBS with policy measurement
  add_key_to_kbs_db ${measurement}
  
  # Start the service/deployment/pod
  esudo kubectl apply -f "${TEST_DIR}/encrypted-image-tests-es.yaml"

  # Retrieve pod name, wait for it to come up, retrieve pod ip
  pod_name=$(esudo kubectl get pod -o wide | grep encrypted-image-tests-es | awk '{print $1;}')
  kubernetes_wait_for_pod_ready_state "$pod_name" 20
  pod_ip=$(esudo kubectl get pod -o wide | grep encrypted-image-tests-es | awk '{print $6;}')

  print_service_info

  # Look for SEV-ES enabled in container dmesg output
  seves_enabled=$(ssh -i ${SSH_KEY_FILE} \
    -o "StrictHostKeyChecking no" \
    -o "PasswordAuthentication=no" \
    -t root@${pod_ip} \
    'dmesg | grep SEV-ES' || true)

  if [ -z "$seves_enabled" ]; then
    >&2 echo -e "${RED}KATA CC TEST - FAIL: SEV-ES is NOT Enabled${NC}"
    return 1
  else
    echo "DMESG REPORT: $seves_enabled"
    echo -e "${GREEN}KATA CC TEST - PASS: SEV-ES is Enabled${NC}"
  fi
}

@test "$test_tag Test signed image with no required measurement" {
  # Add resource files to KBS
  setup_cosign_signatures_files

  #change kernel command line for signature validation
  esudo sed -i 's/agent.enable_signature_verification=false/agent.enable_signature_verification=true/g' ${SEV_CONFIG}

  # Start the service/deployment/pod
  esudo kubectl apply -f "${TEST_DIR}/signed-image-tests.yaml"

  # Retrieve pod name, wait for it to come up, retrieve pod ip
  pod_name=$(esudo kubectl get pod -o wide | grep signed-image-tests | awk '{print $1;}')
  kubernetes_wait_for_pod_ready_state "$pod_name" 20

  print_service_info

  # Save guest qemu kernel append to file, overriding previous to include signature verification
  kernel_append=$(get_guest_kernel_append "${pod_name}")
  echo "${kernel_append}" > "${TEST_DIR}/guest-kernel-append"
  echo "Kernel Append Retrieved from QEMU Process: ${kernel_append}"
}

@test "$test_tag Test signed image with no required measurement, but wrong key (failure)" {
  # Add resource files to KBS
  setup_cosign_signatures_files

  #change kernel command line for signature validation
  esudo sed -i 's/agent.enable_signature_verification=false/agent.enable_signature_verification=true/g' ${SEV_CONFIG}

  # Start the service/deployment/pod
  esudo kubectl apply -f "${TEST_DIR}/signed-image-wrong.yaml"

  # Retrieve pod name, wait for it to come up, retrieve pod ip
  pod_name=$(esudo kubectl get pod -o wide | grep signed-image-wrong | awk '{print $1;}')
  kubernetes_wait_for_pod_ready_state "$pod_name" 30 || true

  print_service_info

  # Get pod info
  pod_info=$(esudo kubectl describe pod ${pod_name})

  # Check failure condition
  if [[ ! ${pod_info} =~ "Validate image failed" ]]; then
    >&2 echo -e "${RED}TEST - FAIL${NC}"
    return 1
  else
    echo "Pod message contains: Validate image failed"
    echo -e "${GREEN}TEST - PASS${NC}"
  fi
}

@test "$test_tag Test signed image with required measurement" {
  #change kernel command line for signature validation
  esudo sed -i 's/agent.enable_signature_verification=false/agent.enable_signature_verification=true/g' ${SEV_CONFIG}

  # Generate firmware measurement
  local append=$(cat ${TEST_DIR}/guest-kernel-append)
  echo "Kernel Append: ${append}"
  measurement=$(generate_firmware_measurement_with_append "${append}")
  echo "Firmware Measurement: ${measurement}"

  # Add resource files to KBS
  setup_cosign_signatures_files ${measurement}

  # Start the service/deployment/pod
  esudo kubectl apply -f "${TEST_DIR}/signed-image-tests.yaml"

  # Retrieve pod name, wait for it to come up, retrieve pod ip
  pod_name=$(esudo kubectl get pod -o wide | grep signed-image-tests | awk '{print $1;}')
  kubernetes_wait_for_pod_ready_state "$pod_name" 50

  print_service_info
}

@test "$test_tag Test signed image with INVALID measurement" {
  #change kernel command line for signature validation
  esudo sed -i 's/agent.enable_signature_verification=false/agent.enable_signature_verification=true/g' ${SEV_CONFIG}

  # Generate firmware measurement
  local append="INVALID-INPUT"
  measurement=$(generate_firmware_measurement_with_append ${append})
  echo "Firmware Measurement: ${measurement}"

  # Add resource files to KBS
  setup_cosign_signatures_files ${measurement}

  # Start the service/deployment/pod
  esudo kubectl apply -f "${TEST_DIR}/signed-image-tests.yaml"

  # Retrieve pod name, wait for it to come up, retrieve pod ip
  pod_name=$(esudo kubectl get pod -o wide | grep signed-image-tests | awk '{print $1;}')
  kubernetes_wait_for_pod_ready_state "$pod_name" 20 || true

  print_service_info

  # Check failure condition
  if [[ ! ${pod_info} =~ "Policy validation" ]]; then
    >&2 echo -e "${RED}TEST - FAIL${NC}"
    return 1
  else
    echo "Pod message contains: Policy validation failed"
    echo -e "${GREEN}TEST - PASS${NC}"
  fi
}

teardown_file() {
  echo "###############################################################################"
  echo -e "TEARDOWN - STARTED\n"

  # Allow to not destroy the environment if you are developing/debugging tests
  if [[ "${CI:-false}" == "false" && "${DEBUG:-}" == true ]]; then
    echo "Leaving changes and created resources untouched"
    return
  fi

  # Remove the service/deployment/pod
  delete_pods

  # Stop KBS and KBS DB containers
  (cd ${KBS_DIR}/simple-kbs && esudo docker-compose down 2>/dev/null)

  # Cleanup directories
  esudo rm -rf "${KBS_DIR}"
  esudo rm -rf "${TEST_DIR}"

  echo "TEARDOWN - COMPLETE"
  echo "###############################################################################"
}
