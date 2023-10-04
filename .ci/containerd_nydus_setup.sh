#!/bin/bash
#
# Copyright (c) 2023 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail

cidir=$(dirname "$0")
source "${cidir}/../lib/common.bash"

# Nydus related configurations
NYDUS_SNAPSHOTTER_BINARY="/usr/local/bin/containerd-nydus-grpc"
NYDUS_SNAPSHOTTER_TARFS_CONFIG="/usr/local/share/nydus-snapshotter/config-coco-host-sharing.toml"
NYDUS_SNAPSHOTTER_GUEST_CONFIG="/usr/local/share/nydus-snapshotter/config-coco-guest-pulling.toml"
NYDUS_SNAPSHOTTER_CONFIG="${NYDUS_SNAPSHOTTER_CONFIG:-${NYDUS_SNAPSHOTTER_TARFS_CONFIG}}"
NYDUS_SNAPSHOTTER_TARFS_EXPORT_MODE="${PULL_ON_HOST_EXPORT_MODE:-image_block}"

echo "Configure nydus snapshotter"
if [ "${IMAGE_OFFLOAD_TO_GUEST:-"no"}" == "yes" ]; then
	echo "Pulling image on the guest"
	NYDUS_SNAPSHOTTER_CONFIG="${NYDUS_SNAPSHOTTER_GUEST_CONFIG}"
else
	echo "Pulling image on the host | export_mode = ${NYDUS_SNAPSHOTTER_TARFS_EXPORT_MODE}"
	NYDUS_SNAPSHOTTER_CONFIG="${NYDUS_SNAPSHOTTER_TARFS_CONFIG}"
	sudo sed -i "s/export_mode = .*/export_mode = \"${NYDUS_SNAPSHOTTER_TARFS_EXPORT_MODE}\"/" "$NYDUS_SNAPSHOTTER_CONFIG"
fi

echo "Start nydus snapshotter"
sudo "${NYDUS_SNAPSHOTTER_BINARY}" --config "${NYDUS_SNAPSHOTTER_CONFIG}" >/dev/stdout 2>&1 &

echo "Configure containerd to use the nydus snapshotter"

containerd_config_file="/etc/containerd/config.toml"

snapshotter_socket="/run/containerd-nydus/containerd-nydus-grpc.sock"
proxy_config="  [proxy_plugins.nydus]\n    type = \"snapshot\"\n    address = \"${snapshotter_socket}\""
snapshotter_config="      disable_snapshot_annotations = false\n      snapshotter = \"nydus\""

echo -e "[proxy_plugins]" | sudo tee -a "${containerd_config_file}"
echo -e "${proxy_config}" | sudo tee -a "${containerd_config_file}"

sudo sed -i '/\[plugins.cri.containerd\]/a\'"${snapshotter_config}" "${containerd_config_file}"
sudo systemctl restart containerd

# SNP & SEV tests seem to need time for containerd and snapshotter to be running
# In future fix this to make it check if it's running rather than sleep
sleep 30
