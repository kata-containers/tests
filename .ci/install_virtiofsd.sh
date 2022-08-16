#!/bin/bash
#
# Copyright (c) 2022 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

cidir=$(dirname "$0")
source "${cidir}/lib.sh"

DESTDIR="${DESTDIR:-/}"
KATA_BUILD_CC="${KATA_BUILD_CC:-no}"

main() {
	bash "${cidir}/install_rust.sh" && source "$HOME/.cargo/env"

	build_static_artifact_and_install "virtiofsd"

	# Kata CI requires the link but this isn't true to all scenarios,
	# for example, on OpenShift CI everything should be installed under
	# /opt/kata. So do not try to create the link unless the directory
	# exist.
	if [ -d "${DESTDIR}/usr/libexec" -a "${KATA_BUILD_CC}" == "no" ]; then
		sudo ln -sf "${DESTDIR}/opt/kata/libexec/virtiofsd" \
			"${DESTDIR}/usr/libexec/virtiofsd"
	fi
}

main "$@"
