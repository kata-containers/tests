#/bin/bash
#
# Copyright (c) 2018 HyperHQ Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
# This test will perform test to validate kata containers with
# factory  vmcache enabled using shimv2 + containerd + cri 

SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
source "${SCRIPT_PATH}/../../../metrics/lib/common.bash"
source /etc/os-release || source /usr/lib/os-release

echo "========================================"
echo "start factory vmcache testing"
echo "========================================"

export FACTORY_VMCACHE_TEST=true
${SCRIPT_PATH}/../cri/integration-tests.sh

