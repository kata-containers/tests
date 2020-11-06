#!/bin/bash
#
# Copyright (c) 2018-2020 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail

readonly kata_runtime_path=$(command -v kata-runtime)
readonly runc_path=$(command -v runc)

sudo mkdir -p /etc/containerd/

cat << EOT | sudo tee /etc/containerd/config.toml
[debug]
  level = "debug"
[plugins]
  [plugins.cri]
    [plugins.cri.containerd]
      [plugins.cri.containerd.runtimes]
        [plugins.cri.containerd.runtimes.runc]
           runtime_type = "io.containerd.runc.v1"
           [plugins.cri.containerd.runtimes.runc.options]
             BinaryName = "${runc_path}"
             Root = ""
        [plugins.cri.containerd.runtimes.kata]
           runtime_type = "io.containerd.kata.v2"
           privileged_without_host_devices = true
EOT
