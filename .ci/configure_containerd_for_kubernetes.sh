#!/bin/bash
#
# Copyright (c) 2021 IBM Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail

echo "Add kubelet containerd configuration"
kubelet_service_dir="/etc/systemd/system/kubelet.service.d/"
sudo mkdir -p "${kubelet_service_dir}"

sudo rm -f "${kubelet_service_dir}/0-crio.conf"
cat << EOF | sudo tee "${kubelet_service_dir}/0-containerd.conf"
[Service]
Environment="KUBELET_EXTRA_ARGS=--container-runtime=remote --runtime-request-timeout=15m --container-runtime-endpoint=unix:///run/containerd/containerd.sock"
EOF

echo "Reload systemd services"
sudo systemctl daemon-reload
