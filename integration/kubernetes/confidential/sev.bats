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

export SEV_CONFIG="/opt/confidential-containers/share/defaults/kata-containers/configuration-qemu-sev.toml"
export RUNTIMECLASS=${RUNTIMECLASS:-"kata"}
export FIXTURES_DIR="${TESTS_REPO_DIR}/integration/kubernetes/confidential/fixtures"
export IMAGE_REPO="ghcr.io/fitzthum/encrypted-image-tests"

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

  local service_yaml_template="${FIXTURES_DIR}/service.yaml.in"

  local service_yaml="${TEST_DIR}/${name}.yaml"
  rm -f "${service_yaml}"
  
  NAME="${name}" IMAGE="${image}" RUNTIMECLASS="${RUNTIMECLASS}" \
    envsubst < "${service_yaml_template}" > "${service_yaml}"
}

configure_containerd() {
  local containerd_config="/etc/containerd/config.toml"

  # Only add the cri_handler if it is not already set
  cri_handler_set=$(cat "${containerd_config}" | grep "cri_handler = \"cc\"" || true)
  if [ -z "${cri_handler_set}" ]; then
    esudo sed -i -e 's/\([[:blank:]]*\)\(runtime_type = "io.containerd.kata.v2"\)/\1\2\n\1cri_handler = "cc"/' "${containerd_config}"
    esudo systemctl restart containerd
  fi
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
    "${TEST_DIR}/unencrypted-image-tests.yaml" 2>/dev/null || true
  esudo kubectl delete -f \
    "${TEST_DIR}/encrypted-image-tests.yaml" 2>/dev/null || true
  
  [ -z "${encrypted_pod_name}" ] || (esudo kubectl wait --for=delete pod/"${encrypted_pod_name}" --timeout=60s || true)
  [ -z "${unencrypted_pod_name}" ] || (esudo kubectl wait --for=delete pod/"${unencrypted_pod_name}" --timeout=60s || true)
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
local append_default="tsc=reliable no_timer_check rcupdate.rcu_expedited=1 \
i8042.direct=1 i8042.dumbkbd=1 i8042.nopnp=1 i8042.noaux=1 noreplace-smp reboot=k \
cryptomgr.notests net.ifnames=0 pci=lastbus=0 console=hvc0 console=hvc1 quiet panic=1 \
nr_cpus=1 scsi_mod.scan=none agent.config_file=/etc/agent-config.toml"

  # Gather firmware locations and kernel append for measurement
  local append=${1:-${append_default}}
  local ovmf_path="/opt/confidential-containers/share/ovmf/OVMF.fd"
  local kernel_path="$(esudo /opt/confidential-containers/bin/kata-runtime \
    --config ${SEV_CONFIG} kata-env --json | jq -r .Kernel.Path)"
  local initrd_path="$(esudo /opt/confidential-containers/bin/kata-runtime \
    --config ${SEV_CONFIG} kata-env --json | jq -r .Initrd.Path)"
  
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

# KBS must be accessible from inside the guest, so update the config file
# with the IP of the host
update_kbs_uri() {
  local kbs_ip="$(ip -o route get to 8.8.8.8 | sed -n 's/.*src \([0-9.]\+\).*/\1/p')"
  local aa_kbc_params="agent.aa_kbc_params=online_sev_kbc::${kbs_ip}:44444"

  # Only add the aa_kbc_params if it is not already set
  aa_kbc_params_set=$(cat "${SEV_CONFIG}" | grep "kernel_params" | grep "${aa_kbc_params}" || true)
  if [ -z "${aa_kbc_params_set}" ]; then
    esudo sed -i -e 's#^\(kernel_params\) = "\(.*\)"#\1 = "\2 '"${aa_kbc_params}"'"#g' "${SEV_CONFIG}"
  fi
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

  configure_containerd

  # KBS setup and run
  echo "Setting up simple-kbs..."
  run_kbs

  # Pull unencrypted image and retrieve encryption and ssh keys
  echo "Pulling unencrypted image and setting keys..."
  pull_unencrypted_image_and_set_keys

  generate_service_yaml "unencrypted-image-tests" "${IMAGE_REPO}:unencrypted"
  generate_service_yaml "encrypted-image-tests" "${IMAGE_REPO}:encrypted"

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
  # Turn off pre-attestation. It is not necessary for an unencrypted image.
  esudo sed -i 's/guest_pre_attestation = true/guest_pre_attestation = false/g' ${SEV_CONFIG}
  
  # Start the service/deployment/pod
  esudo kubectl apply -f "${TEST_DIR}/unencrypted-image-tests.yaml"
  
  # Retrieve pod name, wait for it to come up, retrieve pod ip
  pod_name=$(esudo kubectl get pod -o wide | grep unencrypted-image-tests | awk '{print $1;}')
  esudo kubectl wait --for=condition=ready pod/"$pod_name" --timeout=20s
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

  # Re-enable pre-attestation for the next tests
  esudo sed -i 's/guest_pre_attestation = false/guest_pre_attestation = true/g' ${SEV_CONFIG}
}

@test "$test_tag Test SEV encrypted container launch failure with INVALID measurement" {
  # Update kata config to point to KBS
  # This test expects an invalid measurement, but we still update
  # config so that the kernel params (which are saved) are correct
  update_kbs_uri

  # Generate firmware measurement
  local append="INVALID INPUT"
  measurement=$(generate_firmware_measurement_with_append ${append})
  echo "Firmware Measurement: ${measurement}"

  # Add key to KBS with policy measurement
  add_key_to_kbs_db ${measurement}
  
  # Start the service/deployment/pod
  esudo kubectl apply -f "${TEST_DIR}/encrypted-image-tests.yaml"
  
  # Retrieve pod name, wait for it to fail
  pod_name=$(esudo kubectl get pod -o wide | grep encrypted-image-tests | awk '{print $1;}')
  esudo kubectl wait --for=condition=ready pod/"$pod_name" --timeout=20s || true

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
  esudo kubectl wait --for=condition=ready pod/"$pod_name" --timeout=20s
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
  esudo kubectl wait --for=condition=ready pod/"$pod_name" --timeout=20s
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
