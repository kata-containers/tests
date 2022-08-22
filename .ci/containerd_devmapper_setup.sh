#!/bin/bash
#
# Copyright (c) 2021 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail

cidir=$(dirname "$0")
source "${cidir}/../lib/common.bash"

USE_DEVMAPPER="${USE_DEVMAPPER:-false}"

containerd_config_dir="/etc/containerd"
containerd_config_file="${containerd_config_dir}/config.toml"

if [ "$USE_DEVMAPPER" != "true" ]; then
	echo "WARNING: Devicemapper configuration was not explicitly required. Exiting"
	exit 0
fi

sudo rm -rf /var/lib/containerd/devmapper/data-disk.img
sudo rm -rf /var/lib/containerd/devmapper/meta-disk.img
sudo mkdir -p /var/lib/containerd/devmapper
sudo truncate --size 10G /var/lib/containerd/devmapper/data-disk.img
sudo truncate --size 10G /var/lib/containerd/devmapper/meta-disk.img

sudo mkdir -p /etc/systemd/system

cat<<EOF | sudo tee /etc/systemd/system/containerd-devmapper.service
[Unit]
Description=Setup containerd devmapper device
DefaultDependencies=no
After=systemd-udev-settle.service
Before=lvm2-activation-early.service
Wants=systemd-udev-settle.service
[Service]
Type=oneshot
RemainAfterExit=true
ExecStart=-/sbin/losetup /dev/loop20 /var/lib/containerd/devmapper/data-disk.img
ExecStart=-/sbin/losetup /dev/loop21 /var/lib/containerd/devmapper/meta-disk.img
[Install]
WantedBy=local-fs.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now containerd-devmapper

# Time to setup the thin pool for consumption.
# The table arguments are such.
# start block in the virtual device
# length of the segment (block device size in bytes / Sector size (512)
# metadata device
# block data device
# data_block_size Currently set it 512 (128KB)
# low_water_mark. Copied this from containerd snapshotter test setup
# no. of feature arguments
# Skip zeroing blocks for new volumes.
sudo dmsetup create contd-thin-pool \
	--table "0 20971520 thin-pool /dev/loop21 /dev/loop20 512 32768 1 skip_block_zeroing"

sudo mkdir -p "$containerd_config_dir"
if [ -f "$containerd_config_file" ]
then
	sudo sed -i 's|^\(\[plugins\]\).*|\1\n  \[plugins.devmapper\]\n    pool_name = \"contd-thin-pool\"\n    base_image_size = \"4096MB\"|' "$containerd_config_file"
	sudo sed -i 's|\(\[plugins.cri.containerd\]\).*|\1\n      snapshotter = \"devmapper\"|' "$containerd_config_file"
	sudo cat ${containerd_config_file}
else
	cat<<EOF | sudo tee $containerd_config_file
[plugins]
  [plugins.devmapper]
    pool_name = "contd-thin-pool"
    base_image_size = "4096MB"
  [plugins.cri]
    [plugins.cri.containerd]
      snapshotter = "devmapper"
EOF
fi

restart_containerd_service
