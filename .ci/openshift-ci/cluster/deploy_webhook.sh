#!/bin/bash
#
# Copyright (c) 2021 Red Hat, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
# This script builds the kata-webhook and deploys it in the test cluster.
#
# You should export the KATA_RUNTIME variable with the runtimeclass name
# configured in your cluster in case it is not the default "kata".
#
set -e

script_dir="$(dirname $0)"
webhook_dir="${script_dir}/../../../kata-webhook"
source "${script_dir}/../../lib.sh"

pushd "${webhook_dir}" >/dev/null
# Build and deploy the webhook
#
info "Builds the kata-webhook"
./create-certs.sh
info "Deploys the kata-webhook"
oc apply -f deploy/
# Check the webhook was deployed and is working.
./webhook-check.sh
popd >/dev/null
