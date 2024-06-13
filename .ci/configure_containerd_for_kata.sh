#!/bin/bash
#
# Copyright (c) 2018-2020 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail

PREFIX="${PREFIX:-/opt/kata}"
readonly runc_path=$(command -v runc)

sudo mkdir -p /etc/containerd/

cat << EOF | sudo tee /etc/containerd/config.toml
version = 2
[debug]
  level = "debug"
[plugins]
  [plugins.cri]
    disable_hugetlb_controller = false
    [plugins.cri.containerd]
      [plugins.cri.containerd.runtimes]
        [plugins.cri.containerd.runtimes.runc]
           runtime_type = "io.containerd.runc.v2"
           [plugins.cri.containerd.runtimes.runc.options]
             BinaryName = "${runc_path}"
             Root = ""
        [plugins.cri.containerd.runtimes.kata]
           runtime_type = "io.containerd.kata.v2"
           privileged_without_host_devices = true
           [plugins.cri.containerd.runtimes.kata.options]
              ConfigPath = "${PREFIX}/share/defaults/kata-containers/configuration.toml"
    [plugins.cri.registry.mirrors."localhost:5000"]
      endpoint = ["http://localhost:5000"]
EOF
