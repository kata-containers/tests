#
# Copyright (c) 2017-2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

ifneq (,$(wildcard /usr/lib/os-release))
include /usr/lib/os-release
else
include /etc/os-release
endif

# The time limit in seconds for each test
TIMEOUT := 120

PODMAN_DEPENDENCY = podman
ifeq (${CI}, true)
        ifneq (${TEST_CGROUPSV2}, true)
                PODMAN_DEPENDENCY =
        endif
endif

# union for 'make test'
UNION := kubernetes

# filter scheme script for docker integration test suites
FILTER_FILE = .ci/filter/filter_docker_test.sh

# skipped docker integration tests for Firecraker
# Firecracker configuration file
FIRECRACKER_CONFIG = .ci/hypervisors/firecracker/configuration_firecracker.yaml
# Cloud hypervisor configuration file
CLH_CONFIG = .ci/hypervisors/clh/configuration_clh.yaml
ifneq ($(wildcard $(FILTER_FILE)),)
SKIP_FIRECRACKER := $(shell bash -c '$(FILTER_FILE) $(FIRECRACKER_CONFIG)')
SKIP_CLH := $(shell bash -c '$(FILTER_FILE) $(CLH_CONFIG)')
endif

# get arch
ARCH := $(shell bash -c '.ci/kata-arch.sh -d')

ARCH_DIR = arch
ARCH_FILE_SUFFIX = -options.mk
ARCH_FILE = $(ARCH_DIR)/$(ARCH)$(ARCH_FILE_SUFFIX)

INSTALL_FILES := $(wildcard .ci/install_*.sh)
INSTALL_TARGETS := $(INSTALL_FILES:.ci/install_%.sh=install-%)

# Load architecture-dependent settings
ifneq ($(wildcard $(ARCH_FILE)),)
include $(ARCH_FILE)
endif

default: checkcommits github-labels

checkcommits:
	make -C cmd/checkcommits

github-labels:
	make -C cmd/github-labels

spell-check-dictionary:
	make -C cmd/check-spelling

check-markdown:
	make -C cmd/check-markdown

ginkgo:
	ln -sf . vendor/src
	GOPATH=$(PWD)/vendor go build ./vendor/github.com/onsi/ginkgo/ginkgo
	unlink vendor/src

docker: ginkgo
ifeq ($(RUNTIME),)
	$(error RUNTIME is not set)
endif

ifeq ($(KATA_HYPERVISOR),firecracker)
	./ginkgo -failFast -v -focus "${FOCUS}" -skip "${SKIP_FIRECRACKER}" \
		./integration/docker/ -- -runtime=${RUNTIME} -timeout=${TIMEOUT} \
		-hypervisor=$(KATA_HYPERVISOR)
else ifeq ($(KATA_HYPERVISOR),cloud-hypervisor)
	./ginkgo -failFast -v -focus "${FOCUS}" -skip "${SKIP_CLH}" \
		./integration/docker/ -- -runtime=${RUNTIME} -timeout=${TIMEOUT} \
		-hypervisor=$(KATA_HYPERVISOR)
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
	./integration/cri-o/cri-o.sh

ksm:
	bash -f integration/ksm/ksm_test.sh

kubernetes:
	bash -f .ci/install_bats.sh
	bash -f integration/kubernetes/run_kubernetes_tests.sh

kubernetes-e2e:
	cd "integration/kubernetes/e2e_conformance" &&\
	cat skipped_tests_e2e.yaml &&\
	bash ./setup.sh &&\
	bash ./run.sh

sandbox-cgroup:
	bash -f integration/sandbox_cgroup/sandbox_cgroup_test.sh

stability:
	cd integration/stability && \
	ITERATIONS=2 MAX_CONTAINERS=20 ./soak_parallel_rm.sh
	cd integration/stability && ./hypervisor_stability_kill_test.sh

shimv2:
	bash integration/containerd/shimv2/shimv2-tests.sh
	bash integration/containerd/shimv2/shimv2-factory-tests.sh

cri-containerd:
	bash integration/containerd/cri/integration-tests.sh

log-parser:
	make -C cmd/log-parser

pentest:
	bash -f pentest/all.sh

qat:
	bash integration/qat/qat_test.sh

agent-shutdown:
	bash tracing/test-agent-shutdown.sh

# Tracing requires the agent to shutdown cleanly,
# so run the shutdown test first.
tracing: agent-shutdown
	bash tracing/tracing-test.sh

vcpus:
	bash -f integration/vcpus/default_vcpus_test.sh

pmem:
	bash -f integration/pmem/pmem_test.sh

filesystem:
	bash -f ./conformance/posixfs/fstests.sh

test: ${UNION}

check: checkcommits log-parser

$(INSTALL_TARGETS): install-%: .ci/install_%.sh
	@bash -f $<

list-install-targets:
	@echo $(INSTALL_TARGETS) | tr " " "\n"

rootless:
	bash -f integration/rootless/rootless_test.sh

vfio:
#	Skip: Issue: https://github.com/kata-containers/kata-containers/issues/1488
#	bash -f functional/vfio/run.sh -s false -p clh -i image
#	bash -f functional/vfio/run.sh -s true -p clh -i image
	bash -f functional/vfio/run.sh -s false -p qemu -m q35 -i image
	bash -f functional/vfio/run.sh -s true -p qemu -m q35 -i image

help:
	@echo Subsets of the tests can be run using the following specific make targets:
	@echo " $(UNION)" | sed 's/ /\n\t/g'

# PHONY in alphabetical order
.PHONY: \
	check \
	checkcommits \
	crio \
	docker \
	filesystem \
	ginkgo \
	$(INSTALL_TARGETS) \
	kubernetes \
	list-install-targets \
	log-parser \
	pentest \
	qat \
	rootless \
	sandbox-cgroup \
	test \
	tracing \
	vcpus \
	vfio \
	pmem
