#!/bin/bash
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

readonly script_dir=$(dirname $(readlink -f "$0"))
readonly script_name="$(basename "${BASH_SOURCE[0]}")"
# Source to trap error line number
# shellcheck source=../lib/common.bash
source "${script_dir}/../lib/common.bash"
# shellcheck source=./lib.sh
source "${script_dir}/lib.sh"

declare -A sections
declare -A valid_requests
declare -A json_keys

readonly sections=([sandbox_cgroup_only]=runtime [shared_fs]=hypervisor.qemu)
readonly valid_requests=([sandbox_cgroup_only]="true false" [shared_fs]="virtio-fs virtio-9p")
readonly json_keys=([sandbox_cgroup_only]=.Runtime.SandboxCgroupOnly [shared_fs]=.Hypervisor.SharedFS)

option=${1:-}
request=${2:-}

usage(){
	cat <<EOF
Usage:
${script_name} <option> <request>

Valid options and requests:
$(for opt in "${!valid_requests[@]}"
do
	echo "${opt}": "${valid_requests["$opt"]}"
done)

The configuration changes are applied in kata user config:
${KATA_ETC_CONFIG_PATH}

Remove it if you want to use the stateless options.
EOF
	exit 1
}

# need explicit handling of both cases because all errors are trapped
valid=$([[ -n "${option}" ]] && echo $? || echo $?)
# trailing space to match whole words
if [[ "${valid}" == 0 && ! "${!valid_requests[*]} " =~ "${option} " ]]
then
	echo >&2 "ERROR: unknown option: '${option}'"
	valid=1
fi
[[ "${valid}" == 0 ]] || usage

valid=$([[ -n "${request}" ]] && echo $? || echo $?)
if [[ "${valid}" == 0 && ! "${valid_requests["${option}"]} " =~ "${request} " ]]
then
	echo >&2 "ERROR: unknown request: '${request}'"
	valid=1
fi
[[ "${valid}" == 0 ]] || usage

# quote non-boolean request
[[ "$request" =~ ^(true|false)$ ]] || request="\"${request}\""

readonly section="${sections["${option}"]}"
readonly json_key="${json_keys["${option}"]}"

current_value=$(kata-runtime kata-env --json | jq "${json_key}")
if [ "$current_value" == "${request}" ]; then
	info "already ${request}"
	exit 0
fi

kata_config_path=$(kata-runtime kata-env --json | jq -r .Runtime.Config.Path)

bk_suffix="${option}-bk"


if [ -f "${KATA_ETC_CONFIG_PATH}" ] && [ "${KATA_ETC_CONFIG_PATH}" != ${kata_config_path} ]; then
	bk_file="${KATA_ETC_CONFIG_PATH}-${bk_suffix}"
	info "backup ${KATA_ETC_CONFIG_PATH} in ${bk_file}"
	sudo cp "${KATA_ETC_CONFIG_PATH}" "${bk_file}"
fi

if [ "${KATA_ETC_CONFIG_PATH}" != "${kata_config_path}" ]; then
	kata_etc_dir="/etc/kata-containers"
	if [ ! -d "${kata_etc_dir}" ]; then
		sudo mkdir -p "${kata_etc_dir}"
	fi
	info "Creating etc config based on ${kata_config_path}"
	sudo ln -sf "${kata_config_path}" "${KATA_ETC_CONFIG_PATH}"
fi

info "modifying config file : ${KATA_ETC_CONFIG_PATH}"
sudo crudini --set "${KATA_ETC_CONFIG_PATH}" "${section}" "${option}" "${request}"

info "Validate option is ${request}"
current_value=$(kata-runtime kata-env --json | jq "${json_key}")

[ "$current_value" == "${request}" ] || die "The option was not updated"

info "OK"
