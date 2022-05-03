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

# union for 'make test'
UNION := kubernetes

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

crio:
	bash .ci/install_bats.sh
	./integration/cri-o/cri-o.sh

ksm:
	bash -f integration/ksm/ksm_test.sh

kubernetes:
	bash -f .ci/install_bats.sh
	bash -f integration/kubernetes/run_kubernetes_tests.sh

nydus:
	bash -f integration/nydus/nydus_tests.sh

kubernetes-e2e:
	cd "integration/kubernetes/e2e_conformance" &&\
	cat skipped_tests_e2e.yaml &&\
	bash ./setup.sh &&\
	bash ./run.sh

sandbox-cgroup:
	bash -f functional/sandbox_cgroup/sandbox_cgroup_test.sh

stability:
	cd integration/stability && \
	ITERATIONS=2 MAX_CONTAINERS=20 ./soak_parallel_rm.sh
	cd integration/stability && ./hypervisor_stability_kill_test.sh

# Run the static checks on this repository.
static-checks:
	PATH="$(GOPATH)/bin:$(PATH)" .ci/static-checks.sh \
	     "github.com/kata-containers/tests"

shimv2:
	bash integration/containerd/shimv2/shimv2-tests.sh
	bash integration/containerd/shimv2/shimv2-factory-tests.sh

cri-containerd:
	bash integration/containerd/cri/integration-tests.sh

# Run confidential guest tests.
confidential-guest:
	bash functional/confidential-guest/run.sh

# Run the Confidential Containers tests for containerd.
cc-containerd:
# TODO: The Confidential Containers test aren't merged into main yet, so
# disable their execution. They should be enabled again at the point when
# https://github.com/kata-containers/tests/issues/4628 is ready to be merged.
	@echo "No Confidential Containers tests to run yet. Do nothing."
#	bash integration/containerd/confidential/run_tests.sh

log-parser:
	make -C cmd/log-parser

qat:
	bash integration/qat/qat_test.sh

agent-shutdown:
	bash tracing/test-agent-shutdown.sh

# Tracing requires the agent to shutdown cleanly,
# so run the shutdown test first.
tracing: agent-shutdown
	bash tracing/tracing-test.sh

vcpus:
	bash -f functional/vcpus/default_vcpus_test.sh

pmem:
	bash -f integration/pmem/pmem_test.sh

test: ${UNION}

check: checkcommits log-parser

$(INSTALL_TARGETS): install-%: .ci/install_%.sh
	@bash -f $<

list-install-targets:
	@echo $(INSTALL_TARGETS) | tr " " "\n"

rootless:
	bash -f functional/rootless/rootless_test.sh

vfio:
#	Skip: Issue: https://github.com/kata-containers/kata-containers/issues/1488
#	bash -f functional/vfio/run.sh -s false -p clh -i image
#	bash -f functional/vfio/run.sh -s true -p clh -i image
	bash -f functional/vfio/run.sh -s false -p qemu -m q35 -i image
	bash -f functional/vfio/run.sh -s true -p qemu -m q35 -i image

agent: bash -f functional/agent/agent_test.sh

monitor:
	bash -f functional/kata-monitor/run.sh

help:
	@echo Subsets of the tests can be run using the following specific make targets:
	@echo " $(UNION)" | sed 's/ /\n\t/g'
	@echo ''
	@echo "Pull request targets:"
	@echo "	static-checks	- run the static checks on this repository."

# PHONY in alphabetical order
.PHONY: \
	check \
	checkcommits \
	confidential-guest \
	crio \
	$(INSTALL_TARGETS) \
	kubernetes \
	list-install-targets \
	log-parser \
	qat \
	rootless \
	sandbox-cgroup \
	static-checks \
	test \
	tracing \
	vcpus \
	vfio \
	pmem \
	agent
