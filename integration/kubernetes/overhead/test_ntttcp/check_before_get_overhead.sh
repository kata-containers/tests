#!/bin/bash
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

max_tries="180"
try=1

client="ntttcp-client"

while ! kubectl logs "${client}" | grep "INFO: Network activity progressing" >/dev/null; do
	echo "wait until can request to server"
	sleep 1
	try=$((try + 1))
	if ((try >= max_tries)); then
		echo "reached max tries ${max_tries}"
		#show output
		kubectl logs "${client}"
		exit 1
	fi
done

echo "OK"
