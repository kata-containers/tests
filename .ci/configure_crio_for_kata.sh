#!/bin/bash
#
# Copyright (c) 2017-2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail

source /etc/os-release || source /usr/lib/os-release

if [ "$KATA_BUILD_CC" == "yes" ]; then
	PREFIX="${PREFIX:-/opt/confidential-containers}"
fi
PREFIX="${PREFIX:-/opt/kata}"
crio_config_dir="/etc/crio/crio.conf.d"

echo "Configure runtimes map for RuntimeClass feature with drop-in configs"

sudo tee "$crio_config_dir/99-runtimes" > /dev/null <<EOF
[crio.runtime.runtimes.kata]
runtime_path = "/usr/local/bin/containerd-shim-kata-v2"
runtime_root = "/run/vc"
runtime_type = "vm"
runtime_config_path = "${PREFIX}/share/defaults/kata-containers/configuration.toml"
privileged_without_host_devices = true

[crio.runtime.runtimes.runc]
runtime_path = "/usr/local/bin/crio-runc"
runtime_type = "oci"
runtime_root = "/run/runc"
EOF
