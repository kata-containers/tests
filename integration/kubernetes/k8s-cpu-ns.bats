#!/usr/bin/env bats
#
# Copyright (c) 2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

load "${BATS_TEST_DIRNAME}/../../.ci/lib.sh"
load "${BATS_TEST_DIRNAME}/tests_common.sh"

setup() {
	pod_name="constraints-cpu-test"
	container_name="first-cpu-container"
	sharessyspath="/sys/fs/cgroup/cpu/cpu.shares"
	quotasyspath="/sys/fs/cgroup/cpu/cpu.cfs_quota_us"
	periodsyspath="/sys/fs/cgroup/cpu/cpu.cfs_period_us"
	total_cpus=2
	total_requests=512
	total_cpu_container=1
	num_cpus_cmd='grep -e "^processor" /proc/cpuinfo |wc -l'

	get_pod_config_dir
}

@test "Check CPU constraints" {
	# Create the pod
	kubectl create -f "${pod_config_dir}/pod-cpu.yaml"

	# Check pod creation
	kubectl wait --for=condition=Ready --timeout=$timeout pod "$pod_name"

	retries="10"

	# Check the total of cpus
	for _ in $(seq 1 "$retries"); do
		# Get number of cpus
		total_cpus_container=$(kubectl exec pod/"$pod_name" -c "$container_name" \
			-- sh -c "$num_cpus_cmd")
		# Verify number of cpus
		[ "$total_cpus_container" -le "$total_cpus" ]
		[ "$total_cpus_container" -eq "$total_cpus" ] && break
		sleep 1
	done
	[ "$total_cpus_container" -eq "$total_cpus" ]

	# Check the total of requests
	total_requests_container=$(kubectl exec $pod_name -c $container_name \
		-- sh -c "cat $sharessyspath")

	[ "$total_requests_container" -eq "$total_requests" ]

	# Check the cpus inside the container

	total_cpu_quota=$(kubectl exec $pod_name -c $container_name \
		-- sh -c "cat $quotasyspath")

	total_cpu_period=$(kubectl exec $pod_name -c $container_name \
		-- sh -c "cat $periodsyspath")

	division_quota_period=$(echo $((total_cpu_quota/total_cpu_period)))

	[ "$division_quota_period" -eq "$total_cpu_container" ]
}

teardown() {
	# Debugging information
	kubectl describe "pod/$pod_name"
	kubectl describe "pod/$pod_name"

	kubectl exec "$pod_name" -c "$container_name" -- sh -c "$num_cpus_cmd"

	kubectl delete pod "$pod_name"
}
