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

crio_config_file="/etc/crio/crio.conf"
crio_config_dir="/etc/crio/crio.conf.d"
runc_flag="\/usr\/local\/bin\/crio-runc"
kata_flag="\/usr\/local\/bin\/containerd-shim-kata-v2"

minor_crio_version=$(crio --version | egrep -o "[0-9]+\.[0-9]+\.[0-9]+" | head -1 | cut -d '.' -f2)

if [ "$minor_crio_version" -ge "18" ]; then
	echo "Configure runtimes map for RuntimeClass feature with drop-in configs"
	echo "- Set kata as default runtime"
	sudo tee -a "$crio_config_dir/99-runtime.conf" > /dev/null <<EOF
[crio.runtime]
default_runtime = "kata"
[crio.runtime.runtimes.kata]
runtime_path = "/usr/local/bin/kata-runtime"
runtime_root = "/run/vc"
runtime_type = "oci"
privileged_without_host_devices = true
EOF
elif [ "$minor_crio_version" -ge "12" ]; then
	echo "Configure runtimes map for RuntimeClass feature"
	echo "- Set runc as default runtime"
	runc_configured=$(grep -q $runc_flag $crio_config_file; echo "$?")
	if [[ $runc_configured -ne 0 ]]; then
		sudo sed -i 's!runtime_path =.*!runtime_path = "/usr/local/bin/crio-runc"!' "$crio_config_file"
	fi
	echo "- Add kata-runtime to the runtimes map"
	kata_configured=$(grep -q $kata_flag $crio_config_file; echo "$?")
	if [[ $kata_configured -ne 0 ]]; then
		sudo sed -i '/\/run\/runc/a [crio.runtime.runtimes.kata]' "$crio_config_file"
		sudo sed -i '/crio\.runtime\.runtimes\.kata\]/a runtime_path = "/usr/local/bin/containerd-shim-kata-v2"' "$crio_config_file"
		sudo sed -i '/containerd-shim-kata-v2"/a runtime_root = "/run/vc"' "$crio_config_file"
		sudo sed -i '/\/run\/vc/a runtime_type = "vm"' "$crio_config_file"
		sudo sed -i '/runtime_type = "vm"/a privileged_without_host_devices = true' "$crio_config_file"
	fi
fi
