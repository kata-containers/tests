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

DOCKER_DEPENDENCY = docker
ifeq (${CI}, true)
	ifneq (${TEST_DOCKER}, true)
		DOCKER_DEPENDENCY =
	endif
endif

PODMAN_DEPENDENCY = podman
ifeq (${CI}, true)
        ifneq (${TEST_CGROUPSV2}, true)
                PODMAN_DEPENDENCY =
        endif
endif

CONFORMANCE_DEPENDENCY = conformance
ifeq (${CI}, true)
	ifneq (${TEST_CONFORMANCE}, true)
		CONFORMANCE_DEPENDENCY =
	endif
endif


# union for 'make test'
UNION := crio \
	compatibility \
	configuration \
	$(CONFORMANCE_DEPENDENCY) \
	debug-console \
	$(DOCKER_DEPENDENCY) \
	docker-compose \
	docker-stability \
	entropy \
	functional \
	kubernetes \
	netmon \
	network \
	oci \
	openshift \
	pmem\
	$(PODMAN_DEPENDENCY) \
	ramdisk \
	shimv2 \
	swarm \
	time-drift \
	tracing \
	vcpus \
	vm-factory

# filter scheme script for docker integration test suites
FILTER_FILE = .ci/filter/filter_docker_test.sh

# skipped docker integration tests for Firecraker
# Firecracker configuration file
FIRECRACKER_CONFIG = .ci/hypervisors/firecracker/configuration_firecracker.yaml
# Cloud hypervisor configuration file
CLH_CONFIG = .ci/hypervisors/clh/configuration_clh.yaml
# Rust agent configuration file
RUST_CONFIG = .ci/rust/configuration_rust.yaml
ifneq ($(wildcard $(FILTER_FILE)),)
SKIP_FIRECRACKER := $(shell bash -c '$(FILTER_FILE) $(FIRECRACKER_CONFIG)')
SKIP_CLH := $(shell bash -c '$(FILTER_FILE) $(CLH_CONFIG)')
SKIP_RUST := $(shell bash -c '$(FILTER_FILE) $(RUST_CONFIG)')
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

functional: ginkgo
ifeq (${RUNTIME},)
	$(error RUNTIME is not set)
else
	./ginkgo -failFast -v -focus "${FOCUS}" -skip "${SKIP}" \
		functional/ -- -runtime=${RUNTIME} -timeout=${TIMEOUT}
	bash sanity/check_sanity.sh
endif

debug-console:
	bash -f ./functional/debug_console/run.sh

EXTRA_GINKGO_FLAGS :=
SKIP_GINKGO =
GINKGO_FLAGS := -failFast -v $(EXTRA_GINKGO_FLAGS)

GINKGO_TEST_FLAGS := ./integration/docker/ -- -runtime=${RUNTIME} -timeout=${TIMEOUT} -hypervisor=$(KATA_HYPERVISOR)

# Append strings to skip for ginkgo using '|'
define append_ginkgo
$(info INFO: adding '$(2)' to '$(1)')
$(if $($(1)),$(if $(2),$(eval $(1)= $($(1))|)))
$(if $(2),$(eval $(1) = $($(1))$(2)))
endef

ifeq ($(KATA_HYPERVISOR),cloud-hypervisor)
$(eval $(call append_ginkgo,SKIP_GINKGO,$(SKIP_CLH)))
endif

ifeq ($(KATA_HYPERVISOR),firecracker)
$(eval $(call append_ginkgo,SKIP_GINKGO,$(SKIP_FIRECRACKER)))
endif

ifeq ($(TEST_RUST_AGENT),true)
$(eval $(call append_ginkgo,SKIP_GINKGO,$(SKIP_RUST)))
endif

ifneq ($(SKIP),)
$(eval $(call append_ginkgo,SKIP_GINKGO,$(SKIP)))
endif

RUN_PARALLEL ?= true
ifeq (centos7,$(ID)$(VERSION_ID))
RUN_PARALLEL = false
endif

ifeq ($(ARCH),$(filter $(ARCH), aarch64 s390x ppc64le))
RUN_PARALLEL = false
endif

ifeq ($(KATA_HYPERVISOR),firecracker)
RUN_PARALLEL = false
endif

ifeq ($(KATA_HYPERVISOR),cloud-hypervisor)
RUN_PARALLEL = false
endif

SKIP_GINKGO_SERIAL = $(SKIP_GINKGO)
SKIP_GINKGO_PARALLEL = $(SKIP_GINKGO)
$(eval $(call append_ginkgo,SKIP_GINKGO_PARALLEL,\[Serial Test\]))

ifneq ($(SKIP_GINKGO),)
SKIP_GINKGO_FLAGS = -skip "$(SKIP_GINKGO)"
endif

ifneq ($(SKIP_GINKGO_PARALLEL),)
SKIP_GINKGO_PARALLEL_FLAGS = -skip "$(SKIP_GINKGO_PARALLEL)"
endif

ifneq ($(SKIP_GINKGO_SERIAL),)
SKIP_GINKGO_SERIAL_FLAGS = -skip "$(SKIP_GINKGO_SERIAL)"
endif

ifneq ($(FOCUS),)
$(eval $(call append_ginkgo,FOCUS_GINKGO,$(FOCUS)))
# User requesting specific test, make it serial to simplify view.
RUN_PARALLEL = false
endif

FOCUS_GINKGO_SERIAL = $(FOCUS_GINKGO)
FOCUS_GINKGO_PARALLEL = $(FOCUS_GINKGO)
$(eval $(call append_ginkgo,FOCUS_GINKGO_SERIAL,\[Serial Test\]))

ifneq ($(FOCUS_GINKGO),)
FOCUS_GINKGO_FLAGS = -focus "$(FOCUS_GINKGO)"
endif

ifneq ($(FOCUS_GINKGO_PARALLEL),)
FOCUS_GINKGO_PARALLEL_FLAGS = -focus "$(FOCUS_GINKGO_PARALLEL)"
endif

ifneq ($(FOCUS_GINKGO_SERIAL),)
FOCUS_GINKGO_SERIAL_FLAGS = -focus "$(FOCUS_GINKGO_SERIAL)"
endif

docker: ginkgo
ifeq ($(RUNTIME),)
	$(error RUNTIME is not set)
endif

ifeq (false,$(RUN_PARALLEL))
	@echo "Running test in serial, this will take several minutes"
	./ginkgo  $(GINKGO_FLAGS) $(SKIP_GINKGO_FLAGS) $(FOCUS_GINKGO_FLAGS) $(GINKGO_TEST_FLAGS)
else
	@echo "Running tests in parallel"
	./ginkgo -p -stream $(GINKGO_FLAGS) $(SKIP_GINKGO_PARALLEL_FLAGS) $(FOCUS_GINKGO_PARALLEL_FLAGS) $(GINKGO_TEST_FLAGS)
	@echo "Running tests that only can run in serial"
	./ginkgo $(GINKGO_FLAGS) $(SKIP_GINKGO_SERIAL_FLAGS) $(FOCUS_GINKGO_SERIAL_FLAGS) $(GINKGO_TEST_FLAGS)
	@echo "Running sanity check for docker tests"
	bash sanity/check_sanity.sh
endif

crio:
	bash .ci/install_bats.sh
	RUNTIME=${RUNTIME} ./integration/cri-o/cri-o.sh

configuration:
	bash .ci/install_bats.sh
	cd integration/change_configuration_toml && \
	bats change_configuration_toml.bats

conformance:
	bash -f conformance/posixfs/fstests.sh

docker-compose:
	bash .ci/install_bats.sh
	cd integration/docker-compose && \
	bats docker-compose.bats

docker-stability:
	systemctl is-active --quiet docker || sudo systemctl start docker
	cd integration/stability && \
	export ITERATIONS=2 && export MAX_CONTAINERS=20 && ./soak_parallel_rm.sh
	cd integration/stability && ./bind_mount_linux.sh
	cd integration/stability && ./hypervisor_stability_kill_test.sh

podman:
	bash -f integration/podman/run_podman_tests.sh

kubernetes:
	bash -f .ci/install_bats.sh
	bash -f integration/kubernetes/run_kubernetes_tests.sh

kubernetes-e2e:
	cd "integration/kubernetes/e2e_conformance" &&\
	cat skipped_tests_e2e.yaml &&\
	bash ./setup.sh &&\
	bash ./run.sh

ksm:
	bash -f integration/ksm/ksm_test.sh

sandbox-cgroup:
	bash -f integration/sandbox_cgroup/sandbox_cgroup_test.sh
	bash -f integration/sandbox_cgroup/check_cgroups_sandbox.sh

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

openshift-e2e:
	bash -f integration/openshift/e2e/run_tests.sh

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
	bats integration/entropy/entropy_time.bats

netmon:
	systemctl is-active --quiet docker || sudo systemctl start docker
	bash -f .ci/install_bats.sh
	bats integration/netmon/netmon_test.bats

tracing:
	bash tracing/tracing-test.sh

time-drift:
	bats integration/time_drift/time_drift.bats

compatibility:
	systemctl is-active --quiet docker || sudo systemctl start docker
	bash -f integration/compatibility/run.sh

vcpus:
	bash -f integration/vcpus/default_vcpus_test.sh

vfio:
	bash -f functional/vfio/run.sh -s false -p clh -i image
	bash -f functional/vfio/run.sh -s true -p clh -i image
#   bash -f functional/vfio/run.sh -s false -p clh -i initrd
#   bash -f functional/vfio/run.sh -s true -p clh -i initrd
	bash -f functional/vfio/run.sh -s false -p qemu -m pc -i image
	bash -f functional/vfio/run.sh -s true -p qemu -m pc -i image
	bash -f functional/vfio/run.sh -s false -p qemu -m q35 -i image
	bash -f functional/vfio/run.sh -s true -p qemu -m q35 -i image
	bash -f functional/vfio/run.sh -s false -p qemu -m pc -i initrd
	bash -f functional/vfio/run.sh -s true -p qemu -m pc -i initrd
	bash -f functional/vfio/run.sh -s false -p qemu -m q35 -i initrd
	bash -f functional/vfio/run.sh -s true -p qemu -m q35 -i initrd

ipv6:
	bash -f integration/ipv6/ipv6.sh

pmem:
	bash -f integration/pmem/pmem_test.sh

test: ${UNION}

check: checkcommits log-parser

$(INSTALL_TARGETS): install-%: .ci/install_%.sh
	@bash -f $<

list-install-targets:
	@echo $(INSTALL_TARGETS) | tr " " "\n"

help:
	@echo Subsets of the tests can be run using the following specific make targets:
	@echo " $(UNION)" | sed 's/ /\n\t/g'

# PHONY in alphabetical order
.PHONY: \
	compatibility \
	check \
	checkcommits \
	crio \
	conformance \
	debug-console \
	docker \
	docker-compose \
	docker-stability \
	entropy \
	functional \
	ginkgo \
	$(INSTALL_TARGETS) \
	podman \
	ipv6 \
	kubernetes \
	list-install-targets \
	log-parser \
	oci \
	openshift \
	pentest \
	pmem \
	sandbox-cgroup \
	swarm \
	netmon \
	network \
	ramdisk \
	test \
	tracing \
	vcpus \
	vfio \
	vm-factory
