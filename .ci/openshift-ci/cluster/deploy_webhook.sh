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
hello_pod_name="hello-openshift"
kata_runtimeclass_name=${KATA_RUNTIME:-kata}

source "${script_dir}/../../lib.sh"

pushd "${webhook_dir}" >/dev/null
# Build and deploy the webhook
#
info "Builds the kata-webhook"
./create-certs.sh
info "Deploys the kata-webhook"
oc apply -f deploy/
# Wait until it is not available.
oc wait deployment/pod-annotate-webhook --for condition=Available --timeout 60s\
	|| die "The webhook is still unavailable after 60s"

# Check the web-hook is working as expected.
#
[ oc get pod/${hello_pod_name} &>/dev/null ] && \
	die "${hello_pod_name} pod exists, cannot reliably check the webhook"
oc apply -f https://raw.githubusercontent.com/openshift/origin/master/examples/${hello_pod_name}/hello-pod.json
class_name=$(oc get -o jsonpath='{.spec.runtimeClassName}' \
	pod/${hello_pod_name})
oc delete pod/${hello_pod_name}
[ "$class_name" != "$kata_runtimeclass_name" ] && \
	die "kata-webhook is not working"
info "kata-webhook is up and working"
popd >/dev/null
