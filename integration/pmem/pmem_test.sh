#!/bin/bash
#
# Copyright (c) 2021 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

dir_path=$(dirname "$0")
source "${dir_path}/../../lib/common.bash"
source "${dir_path}/../../.ci/lib.sh"
source /etc/os-release || source /usr/lib/os-release
TEST_INITRD="${TEST_INITRD:-no}"
experimental_qemu="${experimental_qemu:-false}"
arch=$("${dir_path}"/../../.ci/kata-arch.sh -d)
CI_JOB="${CI_JOB:-}"

if [ "$TEST_INITRD" == "yes" ]; then
	echo "Skip pmem test: nvdimm is disabled when initrd is used as rootfs"
	exit 0
fi

if [ "$experimental_qemu" == "true" ]; then
	echo "Skip pmem test: experimental qemu doesn't have libpmem support"
	exit 0
fi

if [ "$arch" == "aarch64" ]; then
	echo "Skip pmem test: $arch can't ensure data persistence for the lack of libpmem support"
	exit 0
fi

if [ "${ID}" != "ubuntu" ]; then
	echo "Skip pmem test: ${ID} distro is not supported"
	exit 0
fi

init() {
	${dir_path}/../../integration/kubernetes/init.sh
}

cleanup() {
	set +e
	if [[ $CI_JOB == "PMEM_BAREMETAL" ]]; then
		kubectl describe pod/my-csi-kata-app
		kubectl get pod --all-namespaces

		pushd pmem-csi
		kubectl delete -f "deploy/common/pmem-kata-app.yaml"
		kubectl delete -f "deploy/common/pmem-kata-pvc.yaml"
		kubectl delete -f "deploy/common/pmem-storageclass-ext4-kata.yaml"
		kubectl delete PmemCSIDeployment/pmem-csi.intel.com
		kubectl delete -f "deploy/crd/pmem-csi.intel.com_pmemcsideployments.yaml"
		kubectl delete -f "deploy/operator/pmem-csi-operator.yaml"
		popd
	fi

	rm -rf pmem-csi
	${dir_path}/../../integration/kubernetes/cleanup_env.sh
}

run_test() {
	pushd pmem-csi

	oper_yml="deploy/operator/pmem-csi-operator.yaml"
	sed -i -e 's|image:.*|image: localhost:5000/pmem-csi-driver:canary|g' \
		-e 's|imagePullPolicy:.*|imagePullPolicy: Always|g' \
		${oper_yml}
	kubectl apply -f "${oper_yml}"

	kubectl apply -f deploy/crd/pmem-csi.intel.com_pmemcsideployments.yaml

	kubectl create -f - <<EOF
apiVersion: pmem-csi.intel.com/v1beta1
kind: PmemCSIDeployment
metadata:
  name: pmem-csi.intel.com
spec:
  deviceMode: direct
  nodeSelector:
    storage: pmem
EOF

	stclass_yml="deploy/common/pmem-storageclass-ext4-kata.yaml"
	kubectl apply -f "${stclass_yml}"

	pvc_yml="deploy/common/pmem-kata-pvc.yaml"
	kubectl apply -f "${pvc_yml}"

	app_yml="deploy/common/pmem-kata-app.yaml"
	sed -i -e 's|io.katacontainers.config.hypervisor.memory_offset:.*|io.katacontainers.config.hypervisor.memory_offset: "4294967296"|g' \
		-e 's|runtimeClassName:.*|runtimeClassName: kata|g' \
		"${app_yml}"
	kubectl apply -f "${app_yml}"

	kubectl wait --for=condition=Ready --timeout=120s pod/my-csi-kata-app
	sleep 5

	popd

	kubectl exec pod/my-csi-kata-app -- df /data | grep pmem
	kubectl exec pod/my-csi-kata-app -- mount | grep pmem | grep data | grep dax
}

setup_pmem_csi() {
	git clone https://github.com/intel/pmem-csi/
	pushd pmem-csi

	make build-images
	make push-images

	kubectl label node $(hostname) storage=pmem
	kubectl label node $(hostname) katacontainers.io/kata-runtime=true
	popd
}

main() {
	trap cleanup EXIT QUIT KILL
	init
	setup_pmem_csi
	[[ $CI_JOB != "PMEM_BAREMETAL" ]] || run_test
}

main
