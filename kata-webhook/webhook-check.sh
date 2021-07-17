#!/bin/bash
#
# Copyright (c) 2021 Red Hat
#
# SPDX-License-Identifier: Apache-2.0
#
# Run this script to check the webhook is deployed and working

set -o errexit
set -o nounset
set -o pipefail

webhook_dir=$(dirname $0)
source "${webhook_dir}/../lib/common.bash"
source "${webhook_dir}/common.bash"

readonly hello_pod="hello-kata-webhook"
# The Pod RuntimeClassName for Kata Containers.
RUNTIME_CLASS="${RUNTIME_CLASS:-"kata"}"

cleanup() {
	{
	kubectl get -n ${WEBHOOK_NS} pod/${hello_pod} && \
		kubectl delete -n ${WEBHOOK_NS} pod/${hello_pod}
	} &>/dev/null
}
trap cleanup EXIT

# Check the deployment exists and is available.
#
check_deployed() {
	kubectl get -n ${WEBHOOK_NS} deployment/${WEBHOOK_SVC} &>/dev/null || \
		die "The ${WEBHOOK_SVC} deployment does not exist"

	kubectl wait -n ${WEBHOOK_NS} deployment/${WEBHOOK_SVC} \
		--for condition=Available --timeout 60s &>/dev/null || \
		die "The ${WEBHOOK_SVC} deployment is unavailable after 60s waiting"
}

# Check the webhook is working as expected.
#
check_working() {
	kubectl get -n ${WEBHOOK_NS} pod/${hello_pod} &>/dev/null && \
		die "${hello_pod} pod exists, cannot reliably check the webhook"

	cat <<-EOF | kubectl apply -f -
	kind: Pod
	apiVersion: v1
	metadata:
	  name: ${hello_pod}
	  namespace: ${WEBHOOK_NS}
	spec:
	  restartPolicy: Never
	  containers:
	    - name: ${hello_pod}
	      image: quay.io/prometheus/busybox:latest
	      command: ["echo", "Hello Webhook"]
	      imagePullPolicy: IfNotPresent
	EOF
	class_name=$(kubectl get -n ${WEBHOOK_NS} \
		-o jsonpath='{.spec.runtimeClassName}' pod/${hello_pod})
	if [ "${class_name}" != "${RUNTIME_CLASS}" ]; then
		warn "RuntimeClassName expected ${RUNTIME_CLASS}, got ${class_name}"
		kubectl describe service/${WEBHOOK_SVC}
		echo "--> service logs"
		kubectl logs service/${WEBHOOK_SVC}
		echo "--> mutatingwebhookconfiguration"
		kubectl describe mutatingwebhookconfiguration/${WEBHOOK_SVC}"
		die "kata-webhook is not working"
	fi
}

main() {
	info "Going to check the kata-webhook installation"
	[ -n "${KUBECONFIG:-}" ] || die "KUBECONFIG should be exported"
	check_deployed
	check_working
	info "kata-webhook is up and working"
}

main $@
