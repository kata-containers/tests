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

while ! kubectl logs ab | grep "HTTP/1.1 200 OK" >/dev/null; do
	echo "wait until ab can request to server"
	sleep 1
	try=$((try + 1))
	if ((try >= max_tries)); then
		echo "reached max tries ${max_tries}"
		#show output
		kubectl logs ab
		exit 1
	fi
done

echo "OK"
