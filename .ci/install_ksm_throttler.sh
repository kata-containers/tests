#!/bin/bash
#
# Copyright (c) 2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o pipefail
set -o nounset

METRICS_CI="${METRICS_CI:-}"
throttler_repo="github.com/kata-containers/ksm-throttler"
throttler_dir="${GOPATH}/src/${throttler_repo}"

go get -d "$throttler_repo"

pushd "$throttler_dir"
make
sudo -E PATH=$PATH make install
popd

# If we are running under the metrics CI system then we do not want the throttler
# to be dynmaically changing the KSM settings under us - we need control of them
# ourselves
if [ -z "${METRICS_CI}" ]; then
	sudo systemctl daemon-reload
	sudo systemctl enable kata-vc-throttler.service
	sudo systemctl start kata-vc-throttler.service
fi
