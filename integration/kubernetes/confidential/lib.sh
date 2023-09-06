#!/bin/bash
# Copyright (c) 2021, 2022 IBM Corporation
# Copyright (c) 2022 Red Hat
#
# SPDX-License-Identifier: Apache-2.0
#
# This provides generic functions to use in the tests.
#
set -e

source "${BATS_TEST_DIRNAME}/../../../lib/common.bash"
source "${BATS_TEST_DIRNAME}/../../../.ci/lib.sh"
FIXTURES_DIR="${BATS_TEST_DIRNAME}/fixtures"

# Delete all pods if any exist, otherwise just return
kubernetes_delete_all_cc_pods_if_any_exists() {
  [ -z "$(kubectl get pods)" ] || \
		kubectl delete --all pods
}

# Wait until the pod is not 'Ready'. Fail if it hits the timeout.
#
# Parameters:
#	$1 - the sandbox ID
#	$2 - wait time in seconds. Defaults to 120. (optional)
#
kubernetes_wait_cc_pod_be_ready() {
	local pod_name="$1"
	local wait_time="${2:-120}"

	kubectl wait --timeout=${wait_time}s --for=condition=ready pods/$pod_name
}

# Create a pod and wait it be ready, otherwise fail.
#
# Parameters:
#	$1 - the pod configuration file.
#
kubernetes_create_cc_pod() {
	local config_file="$1"
	local pod_name=""

	if [ ! -f "${config_file}" ]; then
		echo "Pod config file '${config_file}' does not exist"
		return 1
	fi

	kubectl apply -f ${config_file}
	pod_name=$(${GOPATH}/bin/yq r ${config_file} 'metadata.name')
	if ! kubectl get pod "$pod_name" &> /dev/null; then
		echo "Failed to create the pod"
		return 1
	fi

	if ! kubernetes_wait_cc_pod_be_ready "$pod_name"; then
		# TODO: run this command for debugging. Maybe it should be
		#       guarded by DEBUG=true?
		kubectl get pods "$pod_name"
		return 1
	fi
}

# Retrieve the sandbox ID 
#
retrieve_sandbox_id() {
	sandbox_id=$(ps -ef | grep containerd-shim-kata-v2 | egrep -o "\s\-id [a-z0-9]+" | awk '{print $2}')
}

# Check out the doc repo if required
checkout_doc_repo_dir() {
    local doc_repo=github.com/confidential-containers/documentation
    export doc_repo_dir="${GOPATH}/src/${doc_repo}"    
    mkdir -p $(dirname ${doc_repo_dir}) && sudo chown -R ${USER}:${USER} $(dirname ${doc_repo_dir})
    if [ ! -d "${doc_repo_dir}" ]; then
        git clone https://${doc_repo} "${doc_repo_dir}"
        # Update runtimeClassName from kata-cc to "$RUNTIMECLASS"
        sudo sed -i -e 's/\([[:blank:]]*runtimeClassName: \).*/\1'${RUNTIMECLASS:-kata}'/g' "${doc_repo_dir}/demos/ssh-demo/k8s-cc-ssh.yaml"
        chmod 600 ${doc_repo_dir}/demos/ssh-demo/ccv0-ssh
    fi
}

kubernetes_create_ssh_demo_pod() {
	checkout_doc_repo_dir
	kubectl apply -f "${doc_repo_dir}/demos/ssh-demo/k8s-cc-ssh.yaml" && pod=$(kubectl get pods -o jsonpath='{.items..metadata.name}') && kubectl wait --timeout=120s --for=condition=ready pods/$pod
	kubectl get pod $pod
}

connect_to_ssh_demo_pod() {
	local doc_repo=github.com/confidential-containers/documentation
	local doc_repo_dir="${GOPATH}/src/${doc_repo}"    
	local ssh_command="ssh -i ${doc_repo_dir}/demos/ssh-demo/ccv0-ssh root@$(kubectl get service ccv0-ssh -o jsonpath="{.spec.clusterIP}")"
	echo "Issuing command '${ssh_command}'"
	${ssh_command}
}

kubernetes_delete_ssh_demo_pod_if_exists() {
	local sandbox_name="$1"
	if [ -n "$(kubectl get pods $sandbox_name)" ]; then
		kubernetes_delete_ssh_demo_pod ${sandbox_name}
	fi
}

kubernetes_delete_ssh_demo_pod() {
	checkout_doc_repo_dir
	kubectl delete -f "${doc_repo_dir}/demos/ssh-demo/k8s-cc-ssh.yaml"
	kubectl wait pod/$1 --for=delete --timeout=-30s
}

assert_pod_fail() {
	local container_config="$1"
	echo "In assert_pod_fail: "$container_config

	echo "Attempt to create the container but it should fail"
	! kubernetes_create_cc_pod "$container_config" || /bin/false
}


# Check the logged messages on host have a given message.
# Parameters:
#      $1 - the message
#
# Note: get the logs since the global $test_start_date.
#
assert_logs_contain() {
	local message="$1"
	# Note: with image-rs we get more that the default 1000 lines of logs
	journalctl -x -t kata --since "$test_start_date" -n 100000 | grep "$message"
}

setup_decryption_files_in_guest() {
	checkout_doc_repo_dir
	add_kernel_params "agent.aa_kbc_params=offline_fs_kbc::null"
	cp_to_guest_img "etc" "${doc_repo_dir}/demos/ssh-demo/aa-offline_fs_kbc-keys.json"
}

###############################################################################

# Confidentiality - AMD

# Generate the firmware measurement using sev-snp-measure
generate_firmware_measurement_with_append() {
  local config_file="${1}"
  local append="${2}"
  local mode="${3:-sev}"
  
  # Get vcpu sig, get ovmf, kernel and initrd paths
  local vcpu_sig=$(cpuid -1 --leaf 0x1 --raw | cut -s -f2 -d= | cut -f1 -d" ")
  local ovmf_path=$(grep "firmware = " ${config_file} | cut -d'"' -f2)
  local kernel_path="$(esudo /opt/kata/bin/kata-runtime \
    --config ${config_file} kata-env --json | jq -r .Kernel.Path)"
  local initrd_path="$(esudo /opt/kata/bin/kata-runtime \
    --config ${config_file} kata-env --json | jq -r .Initrd.Path)"
  
  # Return error if files don't exist
  [ -f "${ovmf_path}" ] || return 1
  [ -f "${kernel_path}" ] || return 1
  [ -f "${initrd_path}" ] || return 1

  # Generate digest from sev-snp-measure output - this also inserts measurement values inside OVMF image
  # PATH setting here needed for pip installed binary to be found
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
