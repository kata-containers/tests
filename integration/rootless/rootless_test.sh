#!/bin/bash
#
# Copyright (c) 2021 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

dir_path=$(dirname "$0")
source "${dir_path}/../../lib/common.bash"
source "${dir_path}/../../.ci/lib.sh"
source /etc/os-release || source /usr/lib/os-release
pod_id=""

setup() {
	getent group kvm &>/dev/null || sudo groupadd --system kvm
	sudo chown root:kvm /dev/kvm
	sudo chmod g+rw /dev/kvm
	sudo systemctl start crio
	sudo sed -i -e 's/^# *\(rootless\).*=.*$/\1 = true/g' /usr/share/defaults/kata-containers/configuration.toml
	sudo rm -rf /run/kata-containers/ /run/vc/
}

cleanup() {
	sudo sed -i -e 's/^.*\(rootless\)/# \1/g' /usr/share/defaults/kata-containers/configuration.toml
	sudo crictl stopp "$pod_id" || true
	sudo crictl rmp "$pod_id" || true
}

run() {
	pod_id="$(sudo crictl runp -r kata "${dir_path}/rootless-pod.json")"
	waitForProcess 15 3 "sudo crictl inspectp "$pod_id" | jq '.status.state' | grep 'SANDBOX_READY'"
}

main() {
	trap cleanup EXIT QUIT KILL
	setup
	run
}

main
