#!/usr/bin/env bats
# Copyright 2022 Advanced Micro Devices, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#

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

  # Delete both encrypted and unencrypted pods
  esudo kubectl delete -f \
    "${TESTS_REPO_DIR}/integration/kubernetes/confidential/fixtures/unencrypted-image-tests.yaml" 2>/dev/null || true
  esudo kubectl delete -f \
    "${TESTS_REPO_DIR}/integration/kubernetes/confidential/fixtures/encrypted-image-tests.yaml" 2>/dev/null || true
  
  [ -z "${encrypted_pod_name}" ] || (kubernetes_wait_for_pod_delete_state "${encrypted_pod_name}" || true)
  [ -z "${unencrypted_pod_name}" ] || (kubernetes_wait_for_pod_delete_state "${unencrypted_pod_name}" || true)
}

run_kbs() {
  KBS_DIR="$(mktemp -d /tmp/kbs.XXXXXXXX)"
  pushd "${KBS_DIR}"

  # Retrieve simple-kbs repo and tag from versions.yaml
  local simple_kbs_url=$(get_version "externals.simple-kbs.url")
  local simple_kbs_tag=$(get_version "externals.simple-kbs.tag")

  # Clone and run
  git clone "${simple_kbs_url}" --branch main
  (cd simple-kbs && git checkout -b "branch_${simple_kbs_tag}" "${simple_kbs_tag}")
  (cd simple-kbs && esudo docker-compose up -d)
  
  # Set KBS_DB_HOST to kbs db container IP
  KBS_DB_HOST=$(esudo docker network inspect simple-kbs_default \
    | jq -r '.[].Containers[] | select(.Name | test("simple-kbs[_-]db.*")).IPv4Address' \
    | sed "s|/.*$||g")

  waitForProcess 15 1 "mysql -u${KBS_DB_USER} -p${KBS_DB_PW} -h ${KBS_DB_HOST} -D ${KBS_DB} -e '\q'"
  popd
}

pull_encrypted_image_and_set_keys() {
  # Pull encrypted docker image - test workload
  local encrypted_image_url="quay.io/kata-containers/encrypted-image-tests:encrypted"
  esudo docker pull "${encrypted_image_url}"

  # Get encryption key from docker image label
  ENCRYPTION_KEY=$(esudo docker inspect ${encrypted_image_url} \
    | jq -r '.[0].Config.Labels.enc_key')

  # Get ssh key from docker image label and save to file
  esudo docker inspect ${encrypted_image_url} \
    | jq -r '.[0].Config.Labels.ssh_key' \
    | sed "s|\(-----BEGIN OPENSSH PRIVATE KEY-----\)|\1\n|g" \
    | sed "s|\(-----END OPENSSH PRIVATE KEY-----\)|\n\1|g" \
    > "${SSH_KEY_FILE}"

  # Set permissions on private key file
  chmod 600 "${SSH_KEY_FILE}"
}

generate_firmware_measurement_with_append() {
local append_default="tsc=reliable no_timer_check rcupdate.rcu_expedited=1 \
i8042.direct=1 i8042.dumbkbd=1 i8042.nopnp=1 i8042.noaux=1 noreplace-smp reboot=k \
cryptomgr.notests net.ifnames=0 pci=lastbus=0 console=hvc0 console=hvc1 quiet panic=1 \
nr_cpus=1 scsi_mod.scan=none agent.config_file=/etc/agent-config.toml"

  local sev_config="/opt/confidential-containers/share/defaults/kata-containers/configuration-qemu-sev.toml"

  # Gather firmware locations and kernel append for measurement
  local append=${1:-${append_default}}
  local ovmf_path="/opt/confidential-containers/share/ovmf/OVMF.fd"
  local kernel_path="$(esudo /opt/confidential-containers/bin/kata-runtime \
    --config ${sev_config} kata-env --json | jq -r .Kernel.Path)"
  local initrd_path="$(esudo /opt/confidential-containers/bin/kata-runtime \
    --config ${sev_config} kata-env --json | jq -r .Initrd.Path)"
  
  # Return error if files don't exist
  [ -f "${ovmf_path}" ] || return 1
  [ -f "${kernel_path}" ] || return 1
  [ -f "${initrd_path}" ] || return 1

  # Generate digest from sev-snp-measure output - this also inserts measurement values inside OVMF image
  measurement=$(PATH="${PATH}:${HOME}/.local/bin" sev-snp-measure --mode=sev --output-format=base64 \
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
      INSERT INTO secrets VALUES (10, 'key_id1', '${ENCRYPTION_KEY}', 10);
      INSERT INTO keysets VALUES (10, 'KEYSET-1', '["key_id1"]', 10);
      INSERT INTO policy VALUES (10, '["${measurement}"]', '[]', 0, 0, '[]', now(), NULL, 1);
EOF
  else
    mysql -u${KBS_DB_USER} -p${KBS_DB_PW} -h ${KBS_DB_HOST} -D ${KBS_DB} <<EOF
      INSERT INTO secrets VALUES (10, 'key_id1', '${ENCRYPTION_KEY}', NULL);
      INSERT INTO keysets VALUES (10, 'KEYSET-1', '["key_id1"]', 10);
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
    docker-compose
  pip install sev-snp-measure
  "${TESTS_REPO_DIR}/.ci/install_yq.sh" >&2

  # KBS setup and run
  echo "Setting up simple-kbs..."
  run_kbs

  # Pull image and retrieve encryption and ssh keys
  echo "Pulling encrypted image and setting keys..."
  pull_encrypted_image_and_set_keys

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
EOF
}

@test "$test_tag Test SEV unencrypted container launch success" {
  # Add key to KBS with policy measurement
  add_key_to_kbs_db
  
  # Start the service/deployment/pod
  esudo kubectl apply -f \
    "${TESTS_REPO_DIR}/integration/kubernetes/confidential/fixtures/unencrypted-image-tests.yaml"
  
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
  # Generate firmware measurement
  local append="INVALID INPUT"
  measurement=$(generate_firmware_measurement_with_append ${append})
  echo "Firmware Measurement: ${measurement}"

  # Add key to KBS with policy measurement
  add_key_to_kbs_db ${measurement}
  
  # Start the service/deployment/pod
  esudo kubectl apply -f \
    "${TESTS_REPO_DIR}/integration/kubernetes/confidential/fixtures/encrypted-image-tests.yaml"
  
  # Retrieve pod name, wait for it to fail
  pod_name=$(esudo kubectl get pod -o wide | grep encrypted-image-tests | awk '{print $1;}')
  kubernetes_wait_for_pod_ready_state "$pod_name" 20 || true

  print_service_info

  # Save guest qemu kernel append to file
  kenel_append=$(get_guest_kernel_append "${pod_name}")
  echo "${kenel_append}" > "${TEST_DIR}/guest-kernel-append"
  echo "Kernel Append Retrieved from QEMU Process: ${kenel_append}"

  # Get pod info
  pod_info=$(esudo kubectl describe pod ${pod_name})

  # Check failure condition
  if [[ ! ${pod_info} =~ "fw digest not valid" ]]; then
    >&2 echo -e "${RED}TEST - FAIL${NC}"
    return 1
  else
    echo "Pod message contains: fw digest not valid"
    echo -e "${GREEN}TEST - PASS${NC}"
  fi
}

@test "$test_tag Test SEV encrypted container launch success with NO measurement" {
  # Add key to KBS without a policy measurement
  add_key_to_kbs_db
  
  # Start the service/deployment/pod
  esudo kubectl apply -f \
    "${TESTS_REPO_DIR}/integration/kubernetes/confidential/fixtures/encrypted-image-tests.yaml"

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
  esudo kubectl apply -f \
    "${TESTS_REPO_DIR}/integration/kubernetes/confidential/fixtures/encrypted-image-tests.yaml"

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