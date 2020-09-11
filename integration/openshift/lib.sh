#!/bin/bash
#
# Copyright (c) 2020 Red Hat, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
# Contain helper functions and variables for the OpenShift integration
# test scripts.
#
set -e

# ATTENTION: the caller of this lib should have the tests_dir exported
#            correctly
if [ ! -d "${tests_dir}" ]; then
	echo >&2 "ERROR: Unable to find the Kata Containers tests directory"
	exit 1
fi

source ${tests_dir}/.ci/lib.sh

# The name of the Kubernetes runtimeClass resource for Kata Containers.
#
kata_runtimeclass=${kata_runtimeclass:-kata}

# Build the openshift-tests binary.
#
# Return:
#  The absolute path to the file.
#
function build_openshift_tests()
{
	local openshift_repo="github.com/openshift/origin"
	local repo_dir="${GOPATH}/src/${openshift_repo}"
	local cmd=""
	{
	[ -d "$repo_dir" ] || go get -d $openshift_repo
	pushd "$repo_dir"
		git checkout "release-$(get_version \
			"externals.openshift.meta.newest-version")"
		make WHAT=cmd/openshift-tests
		cmd="$(realpath \
			$(find -type f -executable -name "openshift-tests"))"
	popd
	} &>/dev/null
	[ -n "$cmd" ] || return 1
	echo $cmd
}

# Check if the runtimeClass resource is present in the cluster.
#
function is_runtimeclass_present()
{
	oc get runtimeclass/$kata_runtimeclass &>/dev/null
}

# Check if the Kata Containers admission controller is up and running so
# that any spawned Pod will use the runtimeClass by default.
#
function is_kata_admission_controller_active()
{
	local pod="hello-openshift"

	if ! is_runtimeclass_present; then
		warn "The ${kata_runtimeclass} runtimeClass is not present"
		return 1
	fi

	if oc get pod/${pod} &>/dev/null; then
		warn "pod ${pod} is already created, cannot reliably check"
		return 1
	fi

	# Create a hello world pod and check if it is using the runtimeClass.
	#
	oc apply -f https://raw.githubusercontent.com/openshift/origin/master/examples/hello-openshift/hello-pod.json &>/dev/null
	local class_name=$(oc get -o jsonpath='{.spec.runtimeClassName}' \
		pod/${pod})
	oc delete pod/${pod} &>/dev/null
	if [ "$class_name" != "$kata_runtimeclass" ]; then
		warn "runtimeClass: expected ${kata_runtimeclass}, got ${class_name}"
		return 1
	fi
}

# Create the Kata Containers runtimeClass resource if it is not present.
#
# Params:
#   $1 - handler for this runtimeClass  (default is 'kata').
#
add_kata_runtimeclass() {
	local handler=${1:-kata}
	info "Add the ${kata_runtimeclass} runtimeClass"
	if is_runtimeclass_present; then
		info "runtimeClass is already present"
		return
	fi
	cat <<EOF | oc apply -f - 1>/dev/null
---
kind: RuntimeClass
apiVersion: node.k8s.io/v1beta1
metadata:
  name: $kata_runtimeclass
handler: $handler
overhead:
  podFixed:
    memory: "160Mi"
    cpu: "250m"
scheduling:
  nodeSelector:
    node-role.kubernetes.io/worker: ""
EOF
}

# Prepare the OpenShift cluster to run the e2e tests.
#
configure_cluster() {
	info "Configure the OpenShift cluster"
	add_kata_runtimeclass
	if [ $? -ne 0 ]; then
		warn "Failed to create the runtimeClass"
		return 1
	fi
	create_kata_admission_controller
	if [ $? -ne 0 ]; then
		warn "Failed to deploy the admission controller"
		return 1
	fi
}

# Create and deploy the admission controller webhook for Kata Containers.
#
# Params:
#   $1 - timeout in seconds (default is 60)
#
create_kata_admission_controller() {
	local timeout=${1:-60}
	info "Deploy the admission controller webhook to annotate pods"
	{
	pushd "${tests_dir}/kata-webhook"
	# If the webhook is deployed already, do nothing.
	oc get -f deploy/ &>/dev/null
	if [ $? -ne 0 ]; then
		./create-certs.sh
		oc apply -f deploy/
	fi
	popd
	} &>/dev/null
	# Wait it to become available.
	oc wait deployment/pod-annotate-webhook --for condition=Available \
		--timeout ${timeout}s 1>/dev/null
	if [ $? -ne 0 ]; then
		warn "Failed to deploy the controller"
		return 1
	fi
	is_kata_admission_controller_active
}
