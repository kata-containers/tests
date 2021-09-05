#!/bin/bash
#
# Copyright (c) 2018-2020 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail

readonly runc_path=$(command -v runc)

sudo mkdir -p /etc/containerd/

cat << EOF | sudo tee /etc/containerd/config.toml
[debug]
  level = "debug"
[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    [plugins."io.containerd.grpc.v1.cri".containerd]
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
           runtime_type = "io.containerd.runc.v1"
           [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
             BinaryName = "${runc_path}"
             Root = ""
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.kata]
           runtime_type = "io.containerd.kata.v2"
           privileged_without_host_devices = true
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:5000"]
      endpoint = ["http://localhost:5000"]
EOF
