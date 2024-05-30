#!/bin/bash
#
# Copyright (c) 2019 ARM Limited
#
# SPDX-License-Identifier: Apache-2.0

set -o errexit
set -o nounset
set -o pipefail

source "${SCRIPT_PATH}/../../.ci/lib.sh"

network_plugin_config_file="${SCRIPT_PATH}/../../.ci/${arch}/kubernetes/kube-flannel.yml"

flannel_url="$(get_test_version "externals.flannel.kube-flannel_url")"
curl -fsL $flannel_url -o $network_plugin_config_file

memory_resource="spec.template.spec.containers[*].resources.*.memory"
# install yq if not exist
${SCRIPT_PATH}/../../.ci/install_yq.sh
# Default flannel config has limitation and request for memory, and it may cause OOM on AArch64.
# Though here, we delete memory limitation for all archs, this modified-configuration
# file will only be applied on aarch64.
sudo -E ${SCRIPT_PATH}/../../.ci/yq-shim.sh $memory_resource $network_plugin_config_file d  > /dev/null

network_plugin_config="$network_plugin_config_file"
