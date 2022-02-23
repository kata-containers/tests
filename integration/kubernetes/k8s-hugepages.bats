#
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

load "${BATS_TEST_DIRNAME}/../../.ci/lib.sh"
load "${BATS_TEST_DIRNAME}/tests_common.sh"

setup() {
	extract_kata_env

	pod_name="hugepage-pod"
	get_pod_config_dir

	# Enable hugepages
	sed -i 's/#enable_hugepages = true/enable_hugepages = true/g' ${RUNTIME_CONFIG_PATH}

	old_pages=`cat /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages`

	# Set hugepage-2Mi to 4G(2Mi*2048)
	echo 2048 > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages

	systemctl restart kubelet
}

@test "Hugepages" {
	# Create pod
	kubectl create -f "${pod_config_dir}/pod-hugepage.yaml"

	# Check pod creation
	kubectl wait --for=condition=Ready --timeout=$timeout pod "$pod_name"

	# 536870912 = 1024 * 1024 * 512
	kubectl exec $pod_name mount | grep "nodev on /hugepages type hugetlbfs (rw,relatime,pagesize=2M,size=536870912)"
}


@test "Hugepages and sandbox cgroup" {
	# Enable sandbox_cgroup_only
	# And set default memory to a low value that is not smaller then container's request
	sed -i 's/sandbox_cgroup_only=false/sandbox_cgroup_only=true/g' ${RUNTIME_CONFIG_PATH}
	sed -i 's|^default_memory.*|default_memory = 512|g' $RUNTIME_CONFIG_PATH

	# Create pod
	kubectl create -f "${pod_config_dir}/pod-hugepage.yaml"

	# Check pod creation
	kubectl wait --for=condition=Ready --timeout=$timeout pod "$pod_name"

	# 536870912 = 1024 * 1024 * 512
	kubectl exec $pod_name mount | grep "nodev on /hugepages type hugetlbfs (rw,relatime,pagesize=2M,size=536870912)"

	# Disable sandbox_cgroup_only
	sed -i 's/sandbox_cgroup_only=true/sandbox_cgroup_only=false/g' ${RUNTIME_CONFIG_PATH}
}

teardown() {
	echo $old_pages > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages
	kubectl exec $pod_name mount
	kubectl get pod "$pod_name" -o yaml
	kubectl describe pod "$pod_name"

	kubectl delete pod "$pod_name"

	# Disable sandbox_cgroup_only, in case previous test failed.
	sed -i 's/sandbox_cgroup_only=true/sandbox_cgroup_only=false/g' ${RUNTIME_CONFIG_PATH}

	# Disable hugepages and set default memory back to 2048Mi
	sed -i 's/enable_hugepages = true/#enable_hugepages = true/g' ${RUNTIME_CONFIG_PATH}
	sed -i 's|^default_memory.*|default_memory = 2048|g' $RUNTIME_CONFIG_PATH
}
