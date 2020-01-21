#/bin/bash
#
# Copyright (c) 2018 HyperHQ Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
# This test will perform several tests to validate kata containers with
# shimv2 + containerd + cri

source /etc/os-release || source /usr/lib/os-release
SCRIPT_PATH=$(dirname "$(readlink -f "$0")")

if [ "$ID" == "centos" ]; then
	echo "Skip installation on $ID"
	exit
fi


${SCRIPT_PATH}/../../../.ci/install_cri_containerd.sh
${SCRIPT_PATH}/../../../.ci/install_cni_plugins.sh

export SHIMV2_TEST=true

echo "========================================"
echo "         start shimv2 testing"
echo "========================================"

${SCRIPT_PATH}/../cri/integration-tests.sh
