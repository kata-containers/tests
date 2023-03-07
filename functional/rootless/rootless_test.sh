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
	extract_kata_env
	getent group kvm &>/dev/null || sudo groupadd --system kvm
	sudo chown root:kvm /dev/kvm
	sudo chmod g+rw /dev/kvm
	sudo systemctl start crio
	sudo sed --follow-symlinks -i -e 's/^# *\(rootless\).*=.*$/\1 = true/g' /usr/share/defaults/kata-containers/configuration.toml
	sudo rm -rf /run/kata-containers/ /run/vc/
}

cleanup() {
	sudo sed --follow-symlinks -i -e 's/^.*\(rootless\)/# \1/g' /usr/share/defaults/kata-containers/configuration.toml
	sudo crictl stopp "$pod_id" &>/dev/null || true
	sudo crictl rmp "$pod_id" &>/dev/null || true
}

run() {
	pod_id="$(sudo crictl runp -r kata "${dir_path}/rootless-pod.json")"
	waitForProcess 15 3 "sudo crictl inspectp "$pod_id" | jq '.status.state' | grep 'SANDBOX_READY'"

	# There must be created one and only one temporary user.
	local grep_uid="grep -e '^kata-[0-9]\+' /etc/passwd"
	waitForProcess 5 1 "$grep_uid >/dev/null"
	[ "$(eval $grep_uid | wc -l)" -eq 1 ] || \
		die "Unexpected more than one kata temporary UID"
	local kata_uid="$(eval $grep_uid | cut -d: -f3)"
	local kata_gid="$(eval $grep_uid | cut -d: -f4)"
	[[ -n "$kata_uid" && -n "$kata_gid" ]] || \
		die "Unable to find the kata temporary UID"

	# Assert the QEMU process is owned by that user.
	waitForProcess 10 1 "ps -u "$kata_uid" -o cmd --no-header | \
		grep -q "^${HYPERVISOR_PATH:-qemu}"" || \
		die "Expects the QEMU process be owned by a non-root user"

	# Assert the QEMU files are owned by that user too.
	local pod_dir="/run/user/${kata_uid}/run/vc/vm/${pod_id}"
	[ -d "$pod_dir" ] || \
		die "Unable to find the pod directory: $pod_dir"
	local pod_files=(console.sock qmp.sock pid vhost-fs.sock)
	for file_name in ${pod_files[@]}; do
		local file="${pod_dir}/${file_name}"
		waitForProcess 10 1 "test -e "$file"" || \
			die "File didn't show up: $file"
		[ "$(sudo stat -c %u-%g $file)" == "${kata_uid}-${kata_gid}" ]
	done
}

main() {
	trap cleanup EXIT QUIT KILL
	setup
	run
	echo "rootless test: PASSED"
}

main
