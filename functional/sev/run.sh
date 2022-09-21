#!/bin/bash
# Copyright 2022 Advanced Micro Devices, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#

set -eE
set -o nounset
set -o pipefail

trap cleanup EXIT

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tests_repo_dir="$(realpath "$script_dir/../..")"

export KBS_DB_USER="kbsuser"
export KBS_DB_PW="kbspassword"
export KBS_DB="simple_kbs"
export KBS_DB_TYPE="mysql"

esudo() {
  sudo -E PATH=$PATH "$@"
}

initrd_add_files() {
  rootfs_dir="$(mktemp -d)"
  initrd_path="$(kata-runtime kata-env --json | jq -r .Initrd.Path)"
  
  # Extract gzip initrd into temp directory
  zcat "${initrd_path}" | cpio --extract --preserve-modification-time --make-directories --directory="${rootfs_dir}"
  
  # Copy agent-config.toml to initrd
  esudo cp "functional/sev/fixtures/agent-config.toml" "${rootfs_dir}/etc"

  # Compress and save initrd and cleanup temp directory
  sudo bash -c "cd "${rootfs_dir}" && find . | cpio -H newc -o | gzip -9 > ${initrd_path}"
  rm -rf "$rootfs_dir"
}

install_sevctl_and_export_sev_cert_chain() {
  local build_dir="sevctl"

  if [ ! -d "$build_dir" ]; then
    git clone https://github.com/virtee/sevctl.git "$build_dir"
  else
    (cd "$build_dir" && git pull --rebase origin main)
  fi

  (cd "$build_dir" && cargo build)

  # Export the SEV cert chain
  esudo "${build_dir}/target/debug/sevctl" export -f /opt/sev/cert_chain.cert
}

run_kbs() {
  local build_dir="simple-kbs"

  if [ ! -d "$build_dir" ]; then
    git clone https://github.com/confidential-containers/simple-kbs.git \
	    --branch main "$build_dir"
    (cd simple-kbs && git checkout -b branch_0.1.1 0.1.1)
  fi

  (cd simple-kbs && esudo docker-compose up -d)
  sleep 5
}

calculate_measurement_and_add_to_kbs() {
  local kernel_path="$(kata-runtime kata-env --json | jq -r .Kernel.Path)"
  local initrd_path="$(kata-runtime kata-env --json | jq -r .Initrd.Path)"
  local append="tsc=reliable no_timer_check rcupdate.rcu_expedited=1 i8042.direct=1 i8042.dumbkbd=1 i8042.nopnp=1 i8042.noaux=1 noreplace-smp reboot=k cryptomgr.notests net.ifnames=0 pci=lastbus=0 console=hvc0 console=hvc1 quiet panic=1 nr_cpus=1 agent.config_file=/etc/agent-config.toml"

  # Generate digest from sev-snp-measure output - this also inserts measurement values inside OVMF image
  measurement=$(~/.local/bin/sev-snp-measure --mode=sev --output-format=base64 \
    --ovmf="/usr/share/ovmf/OVMF.fd" \
    --kernel="${kernel_path}" \
    --initrd="${initrd_path}" \
    --append="${append}" \
  )
  if [[ -z "${measurement}" ]]; then >&2 echo "Measurement is invalid"; return 1; fi

  # Get encryption key from docker image label
  enc_key=$(esudo docker inspect quay.io/kata-containers/encrypted-image-tests:encrypted \
    | jq -r '.[0].Config.Labels.enc_key')

  # Add key, keyset and policy with measurement to DB
  mysql -u${KBS_DB_USER} -p${KBS_DB_PW} -h ${KBS_DB_HOST} -D ${KBS_DB} <<EOF
    REPLACE INTO secrets VALUES (10, 'key_id1', '${enc_key}', 10);
    REPLACE INTO keysets VALUES (10, 'KEYSET-1', '["key_id1"]', 10);
    REPLACE INTO policy VALUES (10, '["${measurement}"]', '[]', 0, 0, '[]', now(), NULL, 1);
EOF
}

run_test() {
  pushd test

  # Create pod yaml for encrypted image
  cat > encrypted-image-tests.yaml <<EOF
kind: Service
apiVersion: v1
metadata:
  name: encrypted-image-tests
spec:
  selector:
    app: encrypted-image-tests
  ports:
  - port: 22
---
kind: Deployment
apiVersion: apps/v1
metadata:
  name: encrypted-image-tests
spec:
  selector:
    matchLabels:
      app: encrypted-image-tests
  template:
    metadata:
      labels:
        app: encrypted-image-tests
    spec:
      runtimeClassName: kata
      containers:
      - name: encrypted-image-tests
        image: quay.io/kata-containers/encrypted-image-tests:encrypted
        imagePullPolicy: Always
EOF

  echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
  echo "KATA CC SEV TEST - STARTED"

  # Start the pod and retrieve the name
  esudo kubectl apply -f "encrypted-image-tests.yaml"
  echo "-------------------------------------------------------------------------------"
  sleep 20

  # Log kubectl environment information: nodes, services, deployments, pods
  # Retrieve pod name and IP
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
  pod_ip=$(esudo kubectl get pod -o wide | grep encrypted-image-tests | awk '{print $6;}')
  
  # Get ssh key from docker image label and save to file
  esudo docker inspect quay.io/kata-containers/encrypted-image-tests:encrypted \
    | jq -r '.[0].Config.Labels.ssh_key' \
    | sed "s|\(-----BEGIN OPENSSH PRIVATE KEY-----\)|\1\n|g" \
    | sed "s|\(-----END OPENSSH PRIVATE KEY-----\)|\n\1|g" \
    > encrypted-image-tests

  # Set permissions on private key file
  chmod 600 encrypted-image-tests

  # Look for SEV enabled in container dmesg output
  sev_enabled=$(ssh -i encrypted-image-tests \
    -o "StrictHostKeyChecking no" \
    -t root@${pod_ip} \
    'dmesg | grep SEV' || true)

  if [ -z "$sev_enabled" ]; then
    >&2 echo -e "${RED}KATA CC SEV TEST - FAIL: SEV is NOT Enabled${NC}"
    echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
    exit 1
  else
    echo "DMESG REPORT: $sev_enabled"
    echo -e "${GREEN}KATA CC SEV TEST - PASS: SEV is Enabled${NC}"
    echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
  fi
  popd
}

cleanup() {
  exit_code=$?
  set +eE; set +o nounset +o pipefail

  if [ ${exit_code} -ne 0 ]; then
    >&2 echo -e "${RED}ERROR Encountered with Exit Code: ${exit_code}${NC}"
  fi

  echo "###############################################################################"
  echo "CLEANUP - STARTED"

  # Remove the service/deployment/pod and uninstall kubernetes
  esudo kubectl delete -f test/encrypted-image-tests.yaml 2>/dev/null
  esudo "${tests_repo_dir}/integration/kubernetes/cleanup_env.sh"

  # Stop KBS and KBS DB containers and prune system
  (cd simple-kbs && esudo docker-compose down 2>/dev/null)
  esudo docker system prune -f 2>/dev/null

  echo "Cleanup complete"
  echo "###############################################################################"
  exit $exit_code
}

main() {
  source "$HOME/.cargo/env"
  mkdir -p test

  # Install package dependencies
  esudo apt install -y docker-compose
  pip install sev-snp-measure

  # Pull encrypted docker image - workload
  esudo docker pull quay.io/kata-containers/encrypted-image-tests:encrypted

  # Copy agent-config.toml to initrd image
  initrd_add_files

  # Start kubernetes
  pushd "${tests_repo_dir}"
  #esudo ./.ci/install_cni_plugins.sh
  esudo ./integration/kubernetes/init.sh
  popd

  # sevctl, kbs
  install_sevctl_and_export_sev_cert_chain
  run_kbs

  # Set KBS_DB_HOST to kbs db container IP
  export KBS_DB_HOST=$(esudo docker network inspect simple-kbs_default \
    | jq -r '.[].Containers[] | select(.Name | test("simple-kbs_db.*")).IPv4Address' \
    | sed "s|/.*$||g")

  # Testing
  calculate_measurement_and_add_to_kbs

  # SEV
  run_test
}

main $@
