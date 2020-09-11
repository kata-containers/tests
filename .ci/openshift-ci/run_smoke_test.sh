#!/bin/bash
#
# Copyright (c) 2020 Red Hat, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
# Run a smoke test.
#

script_dir=$(dirname $0)
source ${script_dir}/../lib.sh

pod='http-server'

# Create a pod.
#
info "Creating the ${pod} pod"
oc apply -f ${script_dir}/smoke/${pod}.yaml || \
	die "failed to create ${pod} pod"

# Check it eventually goes to 'running'
#
wait_time=600
sleep_time=10
cmd="oc get pod/${pod} -o jsonpath='{.status.containerStatuses[0].state}' | \
	grep running > /dev/null"
info "Wait until the pod gets running"
waitForProcess $wait_time $sleep_time "$cmd" || timed_out=$?
if [ -n "$timed_out" ]; then
	oc describe pod/${pod}
	oc delete pod/${pod}
	die "${pod} not running"
fi
info "${pod} is running"

# Add a file with the hello message
#
hello_file=/tmp/hello
hello_msg='Hello World'
oc exec ${pod} -- sh -c "echo $hello_msg > $hello_file"

info "Creating the service and route"
oc apply -f ${script_dir}/smoke/service.yaml
oc apply -f ${script_dir}/smoke/route.yaml
sleep 60

host=$(oc get route/http-server-route -o jsonpath={.spec.host})
# The route to port 80 should work and it should serve the pod's '/' filesystem
#
curl ${host}:80${hello_file} -s -o hello_msg.txt
grep "${hello_msg}" hello_msg.txt > /dev/null
test_status=$?
if [ $test_status -eq 0 ]; then
	info "HTTP server is working"
else
	info "HTTP server is unreachable"
fi

info "Deleting resources created"
oc delete route/http-server-route
oc delete service/http-server-service

# Delete the pod.
#
info "Deleting the ${pod} pod"
oc delete pod/${pod} || test_status=$?

exit $test_status
