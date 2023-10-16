#!/bin/bash
# Copyright (c) 2021, 2022 IBM Corporation
# Copyright (c) 2022 Red Hat
#
# SPDX-License-Identifier: Apache-2.0
#
# This provides generic functions to use in the tests.
#
[ -z "${BATS_TEST_FILENAME:-}" ] && set -o errexit -o errtrace -o pipefail -o nounset

source "${BATS_TEST_DIRNAME}/../../../lib/common.bash"
source "${BATS_TEST_DIRNAME}/../../../.ci/lib.sh"
FIXTURES_DIR="${BATS_TEST_DIRNAME}/fixtures"
SHARED_FIXTURES_DIR="${BATS_TEST_DIRNAME}/../../confidential/fixtures"

# Toggle between true and false the service_offload configuration of
# the Kata agent.
#
# Parameters:
#	$1: "on" to activate the service, or "off" to turn it off.
#
# Environment variables:
#	RUNTIME_CONFIG_PATH - path to kata's configuration.toml. If it is not
#			      export then it will figure out the path via
#			      `kata-runtime env` and export its value.
#
switch_image_service_offload() {
	# Load the RUNTIME_CONFIG_PATH variable.
	load_runtime_config_path

	case "$1" in
		"on")
			sudo sed -i -e 's/^\(service_offload\).*=.*$/\1 = true/g' \
				"$RUNTIME_CONFIG_PATH"
			;;
		"off")
			sudo sed -i -e 's/^\(service_offload\).*=.*$/\1 = false/g' \
				"$RUNTIME_CONFIG_PATH"

			;;
		*)
			die "Unknown option '$1'"
			;;
	esac
}

# Toggle between different measured rootfs verity schemes during tests.
#
# Parameters:
#	$1: "none" to disable or "dm-verity" to enable measured boot.
#
# Environment variables:
#	RUNTIME_CONFIG_PATH - path to kata's configuration.toml. If it is not
#			      export then it will figure out the path via
#			      `kata-runtime env` and export its value.
#
switch_measured_rootfs_verity_scheme() {
	# In the case of IBM Secure Execution for Linux, the ultravisor (trusted IBM zSystems CPU firmware),
	# before bootstrapping, performs integrity checks by the measurements in the integrity-protected
	# Secure Execution header which are calculated while a secure image is built based on kernel, cmdline, and initrd.
	if [ "${TEE_TYPE}" == "se" ] && [ "$1" == "dm-verity" ]; then
		skip "test for IBM zSystems & LinuxONE SE"
	fi

	# Load the RUNTIME_CONFIG_PATH variable.
	load_runtime_config_path

	case "$1" in
		"dm-verity"|"none")
			sudo sed -i -e 's/scheme=.* cc_rootfs/scheme='"$1"' cc_rootfs/g' \
				"$RUNTIME_CONFIG_PATH"
			;;
		*)
			die "Unknown option '$1'"
			;;
	esac
}

# Add parameters to the 'kernel_params' property on kata's configuration.toml
#
# Parameters:
#	$1..$N - list of parameters
#
# Environment variables:
#	RUNTIME_CONFIG_PATH - path to kata's configuration.toml. If it is not
#			      export then it will figure out the path via
#			      `kata-runtime env` and export its value.
#
add_kernel_params() {
	local params="$@"
	load_runtime_config_path

	sudo sed -i -e 's#^\(kernel_params\) = "\(.*\)"#\1 = "\2 '"$params"'"#g' \
		"$RUNTIME_CONFIG_PATH"

	if [ "${TEE_TYPE}" = "se" ]; then
		local kernel_params=$(sed -n -e 's#^kernel_params = "\(.*\)"#\1#gp' \
			"$RUNTIME_CONFIG_PATH")
		build_se_image "${kernel_params}"
	fi
}

# Get the 'kernel_params' property on kata's configuration.toml
#
# Environment variables:
#	RUNTIME_CONFIG_PATH - path to kata's configuration.toml. If it is not
#			      export then it will figure out the path via
#			      `kata-runtime env` and export its value.
#
get_kernel_params() {
	load_runtime_config_path

        local kernel_params=$(sed -n -e 's#^kernel_params = "\(.*\)"#\1#gp' \
                "$RUNTIME_CONFIG_PATH")
	echo "$kernel_params"
}

# Clear the 'kernel_params' property on kata's configuration.toml
#
# Environment variables:
#	RUNTIME_CONFIG_PATH - path to kata's configuration.toml. If it is not
#			      export then it will figure out the path via
#			      `kata-runtime env` and export its value.
#
clear_kernel_params() {
	load_runtime_config_path

	sudo sed -i -e 's#^\(kernel_params\) = "\(.*\)"#\1 = ""#g' \
		"$RUNTIME_CONFIG_PATH"
}

# Remove parameters in the 'kernel_params' property on kata's configuration.toml
#
# Parameters:
#	$1 - parameter name
#
# Environment variables:
#	RUNTIME_CONFIG_PATH - path to kata's configuration.toml. If it is not
#			      export then it will figure out the path via
#			      `kata-runtime env` and export its value.
#
remove_kernel_param() {
	local param_name="${1}"
	load_runtime_config_path

	sudo sed -i "/kernel_params = /s/$param_name=[^[:space:]\"]*//g" \
		"$RUNTIME_CONFIG_PATH"
}

# Enable the agent console so that one can open a shell with the guest VM.
#
# Environment variables:
#	RUNTIME_CONFIG_PATH - path to kata's configuration.toml. If it is not
#			      export then it will figure out the path via
#			      `kata-runtime env` and export its value.
#
enable_agent_console() {
	load_runtime_config_path

	sudo sed -i -e 's/^# *\(debug_console_enabled\).*=.*$/\1 = true/g' \
		"$RUNTIME_CONFIG_PATH"
}

enable_full_debug() {
	# Load the RUNTIME_CONFIG_PATH variable.
	load_runtime_config_path

	# Toggle all the debug flags on in kata's configuration.toml to enable full logging.
	sudo sed -i -e 's/^# *\(enable_debug\).*=.*$/\1 = true/g' "$RUNTIME_CONFIG_PATH"

	# Also pass the initcall debug flags via Kernel parameters.
	add_kernel_params "agent.log=debug" "initcall_debug"
}

disable_full_debug() {
	# Load the RUNTIME_CONFIG_PATH variable.
	load_runtime_config_path

	# Toggle all the debug flags off in kata's configuration.toml to enable full logging.
	sudo sed -i -e 's/^# *\(enable_debug\).*=.*$/\1 = false/g' "$RUNTIME_CONFIG_PATH"
}

# Configure containerd for confidential containers. Among other things, it ensures
# the CRI handler is configured to deal with confidential container.
#
# Parameters:
#	$1 - (Optional) file path to where save the current containerd's config.toml
#
# Environment variables:
#	TESTS_CONFIGURE_CC_CONTAINERD - if set to 'no' then this function
#					become bogus.
#
configure_cc_containerd() {
	local saved_containerd_conf_file="${1:-}"
	local containerd_conf_file="/etc/containerd/config.toml"

	# The test caller might want to skip the re-configure. For example, when
	# installed via operator it will assume containerd is in right state
	# already.
	[ "${TESTS_CONFIGURE_CC_CONTAINERD:-yes}" == "yes" ] || return 0

	# Even if we are not saving the original file it is a good idea to
	# restart containerd because it might be in an inconsistent state here.
	sudo systemctl stop containerd
	sleep 5
	[ -n "$saved_containerd_conf_file" ] && \
		sudo cp -f "$containerd_conf_file" "$saved_containerd_conf_file"
	sudo systemctl start containerd
	waitForProcess 30 5 "sudo crictl info >/dev/null"

	# Ensure the cc CRI handler is set.
	if [ "$(sudo crictl info | jq -r '.config.cni.confDir')" = "null" ]; then
		echo "    [plugins.cri.cni]
		  # conf_dir is the directory in which the admin places a CNI conf.
		  conf_dir = \"/etc/cni/net.d\"" | \
			  sudo tee -a "$containerd_conf_file"
	fi

	sudo systemctl restart containerd
	if ! waitForProcess 30 5 "sudo crictl info >/dev/null"; then
		die "containerd seems not operational after reconfigured"
	fi
	sudo iptables -w -P FORWARD ACCEPT
}

#
# Auxiliar functions.
#

# Export the RUNTIME_CONFIG_PATH variable if it not set already.
#
load_runtime_config_path() {
	if [ -z "$RUNTIME_CONFIG_PATH" ]; then
		extract_kata_env
	fi
}

setup_common_signature_files_in_guest() {
	rootfs_directory="etc/containers/"
	signatures_dir="${SHARED_FIXTURES_DIR}/quay_verification/$(uname -m)/signatures"

	if [ ! -d "${signatures_dir}" ]; then
		sudo mkdir "${signatures_dir}"
	fi

	sudo tar -zvxf "${SHARED_FIXTURES_DIR}/quay_verification/$(uname -m)/signatures.tar" -C "${signatures_dir}"

	sudo cp -ar ${SHARED_FIXTURES_DIR}/quay_verification/$(uname -m)/* ${SHARED_FIXTURES_DIR}/quay_verification
	cp_to_guest_img "${rootfs_directory}" "${SHARED_FIXTURES_DIR}/quay_verification"
}

setup_offline_fs_kbc_signature_files_in_guest() {
	# Enable signature verification via kata-configuration by removing the param that disables it
	remove_kernel_param "agent.enable_signature_verification"

	# Set-up required files in guest image
	setup_common_signature_files_in_guest
	add_kernel_params "agent.aa_kbc_params=offline_fs_kbc::null"
	cp_to_guest_img "etc" "${SHARED_FIXTURES_DIR}/offline-fs-kbc/$(uname -m)/aa-offline_fs_kbc-resources.json"
}

setup_offline_fs_kbc_secret_files_in_guest() {
	add_kernel_params "agent.aa_kbc_params=offline_fs_kbc::null"
	cp_to_guest_img "etc" "${SHARED_FIXTURES_DIR}/sealed-secret/offline-fs-kbc/aa-offline_fs_kbc-resources.json"
}

setup_cc_kbc_signature_files_in_guest() {
	# Enable signature verification via kata-configuration by removing the param that disables it
	remove_kernel_param "agent.enable_signature_verification"

	# Set-up required files in guest image
	setup_common_signature_files_in_guest

	# CC KBC is specified as: cc_kbc::http://host_ip:port/, and 60000 is the default port used
	# by the service, as well as the one configured in the Kata Containers rootfs.
	CC_KBS_IP=${CC_KBS_IP:-"$(hostname -I | awk '{print $1}')"}
	CC_KBS_PORT=${CC_KBS_PORT:-"60000"}
	add_kernel_params "agent.aa_kbc_params=cc_kbc::http://${CC_KBS_IP}:${CC_KBS_PORT}/"
}

setup_cosign_signatures_files() {
	# Enable signature verification via kata-configuration by removing the param that disables it
	remove_kernel_param "agent.enable_signature_verification"

	# Set-up required files in guest image
	case "${AA_KBC:-}" in
		"offline_fs_kbc")
			add_kernel_params "agent.aa_kbc_params=offline_fs_kbc::null"
			cp_to_guest_img "etc" "${SHARED_FIXTURES_DIR}/cosign/offline-fs-kbc/$(uname -m)/aa-offline_fs_kbc-resources.json"
			;;
		"cc_kbc")
			# CC KBC is specified as: cc_kbc::host_ip:port, and 60000 is the default port used
			# by the service, as well as the one configured in the Kata Containers rootfs.

			CC_KBS_IP=${CC_KBS_IP:-"$(hostname -I | awk '{print $1}')"}
			CC_KBS_PORT=${CC_KBS_PORT:-"60000"}
			add_kernel_params "agent.aa_kbc_params=cc_kbc::http://${CC_KBS_IP}:${CC_KBS_PORT}/"
			;;
		*)
			;;
	esac
}

setup_signature_files() {
	case "${AA_KBC:-}" in
		"offline_fs_kbc")
			setup_offline_fs_kbc_signature_files_in_guest
			;;
		"cc_kbc")
			setup_cc_kbc_signature_files_in_guest
			;;
		*)
			;;
	esac
}

# In case the tests run behind a firewall where images needed to be fetched
# through a proxy.
# Note: With measured rootfs enabled, we can not set proxy through
# agent config file.
setup_proxy() {
	local https_proxy="${HTTPS_PROXY:-${https_proxy:-}}"
	if [ -n "$https_proxy" ]; then
		echo "Enable agent https proxy"
		add_kernel_params "agent.https_proxy=$https_proxy"
	fi

	local no_proxy="${NO_PROXY:-${no_proxy:-}}"
	if [ -n "${no_proxy}" ]; then
		echo "Enable agent no proxy"
		add_kernel_params "agent.no_proxy=${no_proxy}"
	fi
}

# Sets up the credentials file in the guest image for the offline_fs_kbc
# Note: currrently doesn't configure the signature information, just credentials
#
# Parameters:
#	$1 - The container registry e.g. quay.io/kata-containers/confidential-containers-auth
#
# Environment variables:
#	REGISTRY_CREDENTIAL_ENCODED - The base64 encoded version of the registry credentials
#	e.g. echo "username:password" | base64
#
setup_credentials_files() {
	add_kernel_params "agent.aa_kbc_params=offline_fs_kbc::null"

	dest_dir="$(mktemp -t -d offline-fs-kbc-XXXXXXXX)"
	dest_file=${dest_dir}/aa-offline_fs_kbc-resources.json
	auth_json=$(REGISTRY=$1 CREDENTIALS="${REGISTRY_CREDENTIAL_ENCODED}" envsubst < "${SHARED_FIXTURES_DIR}/offline-fs-kbc/auth.json.in" | base64 -w 0)
	CREDENTIAL="${auth_json}" envsubst < "${SHARED_FIXTURES_DIR}/offline-fs-kbc/aa-offline_fs_kbc-resources.json.in" > "${dest_file}"
	cp_to_guest_img "etc" "${dest_file}"
}

###############################################################################

# simple-kbs

SIMPLE_KBS_DIR="${SIMPLE_KBS_DIR:-/tmp/simple-kbs}"
KBS_DB_USER="${KBS_DB_USER:-kbsuser}"
KBS_DB_PW="${KBS_DB_PW:-kbspassword}"
KBS_DB="${KBS_DB:-simple_kbs}"
#KBS_DB_TYPE="{KBS_DB_TYPE:-mysql}"

# Run the simple-kbs
simple_kbs_run() {
  # Retrieve simple-kbs repo and tag from versions.yaml
  local simple_kbs_url=$(get_test_version "externals.simple-kbs.url")
  local simple_kbs_tag=$(get_test_version "externals.simple-kbs.tag")

  # Cleanup and create installation directory
  esudo rm -rf "${SIMPLE_KBS_DIR}"
  mkdir -p "${SIMPLE_KBS_DIR}"
  pushd "${SIMPLE_KBS_DIR}"

  # Clone and run
  git clone "${simple_kbs_url}" --branch main
  pushd simple-kbs

  # Checkout, build and start
  git checkout -b "branch_${simple_kbs_tag}" "${simple_kbs_tag}"
  esudo docker-compose build
  esudo docker-compose up -d

  # Wait for simple-kbs to start
  waitForProcess 15 1 "esudo docker-compose top | grep -q simple-kbs"
  popd

  # Get simple-kbs database container ip
  local kbs_db_host=$(simple_kbs_get_db_ip)

  # Confirm connection to the database is possible
  waitForProcess 5 1 "mysql -u${KBS_DB_USER} -p${KBS_DB_PW} -h ${kbs_db_host} -D ${KBS_DB} -e '\q'"
  popd
}

# Stop simple-kbs and database containers
simple_kbs_stop() {
  (cd ${SIMPLE_KBS_DIR}/simple-kbs && esudo docker-compose down 2>/dev/null)
}

# Delete all test inserted data in the simple-kbs
simple_kbs_delete_data() {
  # Get simple-kbs database container ip
  local kbs_db_host=$(simple_kbs_get_db_ip)

  # Delete all data with 'id = 10'
  mysql -u${KBS_DB_USER} -p${KBS_DB_PW} -h ${kbs_db_host} -D ${KBS_DB} <<EOF
    DELETE FROM secrets WHERE id = 10;
    DELETE FROM policy WHERE id = 10;
EOF
}

# Get the ip of the simple-kbs database docker container
simple_kbs_get_db_ip() {
  esudo docker network inspect simple-kbs_default \
    | jq -r '.[].Containers[] | select(.Name | test("simple-kbs[_-]db.*")).IPv4Address' \
    | sed "s|/.*$||g"
}

# Add key and keyset to database
# If measurement is provided, add policy with measurement to database
simple_kbs_add_key_to_db() {
  local encryption_key="${1}"
  local measurement="${2}"

  # Get simple-kbs database container ip
  local kbs_db_host=$(simple_kbs_get_db_ip)

  if [ -n "${measurement}" ]; then
    mysql -u${KBS_DB_USER} -p${KBS_DB_PW} -h ${kbs_db_host} -D ${KBS_DB} <<EOF
      INSERT INTO secrets VALUES (10, 'default/key/ssh-demo', '${encryption_key}', 10);
      INSERT INTO policy VALUES (10, '["${measurement}"]', '[]', 0, 0, '[]', now(), NULL, 1);
EOF
  else
    mysql -u${KBS_DB_USER} -p${KBS_DB_PW} -h ${kbs_db_host} -D ${KBS_DB} <<EOF
      INSERT INTO secrets VALUES (10, 'default/key/ssh-demo', '${encryption_key}', NULL);
EOF
  fi
}
