#
# Copyright (c) 2017-2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

# The time limit in seconds for each test
TIMEOUT := 120

# union for 'make test'
UNION := functional debug-console docker crio docker-compose network netmon \
	docker-stability oci openshift kubernetes swarm vm-factory \
	entropy ramdisk shimv2 tracing

# filter scheme script for docker integration test suites
FILTER_FILE = .ci/filter/filter_docker_test.sh

# skipped docker integration tests for Firecraker
# Firecracker configuration file
FIRECRACKER_CONFIG = .ci/hypervisors/firecracker/configuration_firecracker.yaml
ifneq ($(wildcard $(FILTER_FILE)),)
SKIP_FIRECRACKER := $(shell bash -c '$(FILTER_FILE) $(FIRECRACKER_CONFIG)')
endif

# get arch
ARCH := $(shell bash -c '.ci/kata-arch.sh -d')

ARCH_DIR = arch
ARCH_FILE_SUFFIX = -options.mk
ARCH_FILE = $(ARCH_DIR)/$(ARCH)$(ARCH_FILE_SUFFIX)

# Load architecture-dependent settings
ifneq ($(wildcard $(ARCH_FILE)),)
include $(ARCH_FILE)
endif

default: checkcommits github-labels

checkcommits:
	make -C cmd/checkcommits

github-labels:
	make -C cmd/github-labels

check-markdown:
	make -C cmd/check-markdown

ginkgo:
	ln -sf . vendor/src
	GOPATH=$(PWD)/vendor go build ./vendor/github.com/onsi/ginkgo/ginkgo
	unlink vendor/src

functional: ginkgo
ifeq (${RUNTIME},)
	$(error RUNTIME is not set)
else
	./ginkgo -failFast -v functional/ -- -runtime=${RUNTIME} -timeout=${TIMEOUT}
	bash sanity/check_sanity.sh
endif

debug-console:
	bash -f ./functional/debug_console/run.sh

docker: ginkgo
ifeq ($(RUNTIME),)
	$(error RUNTIME is not set)
endif

ifeq ($(KATA_HYPERVISOR),firecracker)
	./ginkgo -failFast -v -focus "${FOCUS}" -skip "${SKIP_FIRECRACKER}" \
		./integration/docker/ -- -runtime=${RUNTIME} -timeout=${TIMEOUT}
else ifeq ($(ARCH),$(filter $(ARCH), aarch64 s390x ppc64le))
	./ginkgo -failFast -v -focus "${FOCUS}" -skip "${SKIP}" \
		./integration/docker/ -- -runtime=${RUNTIME} -timeout=${TIMEOUT}
else ifneq (${FOCUS},)
	./ginkgo -failFast -v -focus "${FOCUS}" -skip "${SKIP}" \
		./integration/docker/ -- -runtime=${RUNTIME} -timeout=${TIMEOUT}
else
	# Run tests in parallel, skip tests that need to be run serialized
	./ginkgo -failFast -p -stream -v -skip "${SKIP}" -skip "\[Serial Test\]" \
		./integration/docker/ -- -runtime=${RUNTIME} -timeout=${TIMEOUT}
	# Now run serialized tests
	./ginkgo -failFast -v -focus "\[Serial Test\]" -skip "${SKIP}" \
		./integration/docker/ -- -runtime=${RUNTIME} -timeout=${TIMEOUT}
	bash sanity/check_sanity.sh
endif

crio:
	bash .ci/install_bats.sh
	RUNTIME=${RUNTIME} ./integration/cri-o/cri-o.sh

docker-compose:
	bash .ci/install_bats.sh
	cd integration/docker-compose && \
	bats docker-compose.bats

docker-stability:
	systemctl is-active --quiet docker || sudo systemctl start docker
	cd integration/stability && \
	export ITERATIONS=2 && export MAX_CONTAINERS=20 && ./soak_parallel_rm.sh
	cd integration/stability && ./bind_mount_linux.sh

kubernetes:
	bash -f .ci/install_bats.sh
	bash -f integration/kubernetes/run_kubernetes_tests.sh

swarm:
	systemctl is-active --quiet docker || sudo systemctl start docker
	bash -f .ci/install_bats.sh
	cd integration/swarm && \
	bats swarm.bats

shimv2:
	bash integration/containerd/shimv2/shimv2-tests.sh
	bash integration/containerd/shimv2/shimv2-factory-tests.sh

cri-containerd:
	bash integration/containerd/cri/integration-tests.sh

log-parser:
	make -C cmd/log-parser

oci:
	systemctl is-active --quiet docker || sudo systemctl start docker
	cd integration/oci_calls && \
	bash -f oci_call_test.sh

openshift:
	bash -f .ci/install_bats.sh
	bash -f integration/openshift/run_openshift_tests.sh

pentest:
	bash -f pentest/all.sh

vm-factory:
	bash -f integration/vm_factory/vm_templating_test.sh


network:
	systemctl is-active --quiet docker || sudo systemctl start docker
	bash -f .ci/install_bats.sh
	bats integration/network/macvlan/macvlan_driver.bats
	bats integration/network/ipvlan/ipvlan_driver.bats
	bats integration/network/disable_net/net_none.bats

ramdisk:
	bash -f integration/ramdisk/ramdisk.sh

entropy:
	bash -f .ci/install_bats.sh
	cd integration/entropy && \
	bats entropy_test.bats

netmon:
	systemctl is-active --quiet docker || sudo systemctl start docker
	bash -f .ci/install_bats.sh
	bats integration/netmon/netmon_test.bats

tracing:
	bash tracing/tracing-test.sh

test: ${UNION}

check: checkcommits log-parser

# PHONY in alphabetical order
.PHONY: \
	check \
	checkcommits \
	crio \
	debug-console \
	docker \
	docker-compose \
	docker-stability \
	entropy \
	functional \
	ginkgo \
	kubernetes \
	log-parser \
	oci \
	openshift \
	pentest \
	swarm \
	netmon \
	network \
	ramdisk \
	test \
	tracing \
	vm-factory
