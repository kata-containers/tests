#!/usr/bin/env bats
#
# Copyright (c) 2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

load "${BATS_TEST_DIRNAME}/../../.ci/lib.sh"
load "${BATS_TEST_DIRNAME}/../../lib/common.bash"
issue="https://github.com/kata-containers/tests/issues/2574"

setup() {
	export KUBECONFIG="$HOME/.kube/config"
	sleep_liveness=20

	get_pod_config_dir
}

@test "Liveness probe" {
	pod_name="liveness-exec"

	# Create pod
	kubectl create -f "${pod_config_dir}/pod-liveness.yaml"

	# Check pod creation
	kubectl wait --for=condition=Ready pod "$pod_name"

	# Check liveness probe returns a success code
	kubectl describe pod "$pod_name" | grep -E "Liveness|#success=1"

	echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
	# Sleep necessary to check liveness probe returns a failure code
	if [ "$CI_JOB" == "CRIO_K8S" ]; then
		sleep 35
	else
		sleep "$sleep_liveness"
	fi

	run kubectl describe pod "$pod_name"
	echo -e $output

	run kubectl get pod "$pod_name" -o yaml
	echo -e $output
	echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"

	kubectl describe pod "$pod_name" | grep "Liveness probe failed"
}


teardown() {
	echo -e "\n################## teardown  \n"

	run kubectl describe pod "$pod_name"
	echo -e $output

	run kubectl get pod "$pod_name" -o yaml
	echo -e $output

	kubectl delete pod "$pod_name"
}
