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
source "${cidir}/lib.sh"

[ "$#" -eq 1 ] || die "Specify configure or unconfigure"

containerd_config_file="/etc/containerd/config.toml"
pod_annotations_sgx="\"sgx.intel.com\/epc\""
pod_annotations_orig="\"io.katacontainers.*\""
pod_annotations_match="pod_annotations \= \[$pod_annotations_orig"

configure_annotation() {
	echo "Configure pod annotations for sgx"
	if !(grep -q "$pod_annotations_sgx" "$containerd_config_file"); then
		sed -i -e 's/'$pod_annotations_orig'/'$pod_annotations_orig', '$pod_annotations_sgx'/g' $containerd_config_file
		systemctl restart containerd
	fi
}

unconfigure_annotation() {
	echo "Remove pod annotations for sgx"
	if grep -q "$pod_annotations_sgx" "$containerd_config_file"; then
		sed -i -e 's/, '$pod_annotations_sgx'//g' $containerd_config_file 
		systemctl restart containerd
	fi
}

main() {
	cmd="$1"

	if !(grep -q "$pod_annotations_match" "$containerd_config_file"); then
		die "'$containerd_config_file' is missing expected pod annotations; check that Kata is set up with kata-deploy"
	fi

	case "$cmd" in
		configure ) configure_annotation ;;
		unconfigure ) unconfigure_annotation ;;
		*) die "invalid command: '$cmd'" ;;
	esac
}

main "$@"
