#
# Copyright (c) 2017-2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

ifeq ($(CI),true)
V              = @
else
V              = 1
endif
Q              = $(V:1=)
QUIET_TEST     = $(Q:@=@echo    '     TEST    '$@;./.ci/kata_chronic.sh )

# The time limit in seconds for each test
TIMEOUT := 60

# union for 'make test'
UNION := functional docker crio docker-compose network netmon docker-stability openshift kubernetes swarm vm-factory entropy ramdisk

# skipped test suites for docker integration tests
SKIP :=

# get arch
ARCH := $(shell bash -c '.ci/kata-arch.sh -d')

ARCH_DIR = arch
ARCH_FILE_SUFFIX = -options.mk
ARCH_FILE = $(ARCH_DIR)/$(ARCH)$(ARCH_FILE_SUFFIX)

# Load architecture-dependent settings
ifneq ($(wildcard $(ARCH_FILE)),)
include $(ARCH_FILE)
endif

default: checkcommits

checkcommits:
	make -C cmd/checkcommits

ginkgo:
	ln -sf . vendor/src
	GOPATH=$(PWD)/vendor go build ./vendor/github.com/onsi/ginkgo/ginkgo
	unlink vendor/src

functional: ginkgo
ifeq (${RUNTIME},)
	$(error RUNTIME is not set)
else
	$(QUIET_TEST) ./ginkgo -v functional/ -- -runtime=${RUNTIME} -timeout=${TIMEOUT}
	$(QUIET_TEST) bash sanity/check_sanity.sh
endif

docker: ginkgo
ifeq ($(RUNTIME),)
	$(error RUNTIME is not set)
else
	$(QUIET_TEST) ./ginkgo --succinct --trace -focus "${FOCUS}" -skip "${SKIP}" ./integration/docker/ -- -runtime=${RUNTIME} -timeout=${TIMEOUT}
	$(QUIET_TEST) bash sanity/check_sanity.sh
endif

crio:
	$(QUIET_TEST) bash .ci/install_bats.sh
	$(QUIET_TEST) bash -c "RUNTIME=${RUNTIME} ./integration/cri-o/cri-o.sh"

docker-compose:
	$(QUIET_TEST) bash .ci/install_bats.sh
	$(QUIET_TEST) bats ./integration/docker-compose/docker-compose.bats

docker-stability:
	$(QUIET_TEST) bash -c "systemctl is-active --quiet docker || sudo systemctl start docker"
	$(QUIET_TEST) bash -c "ITERATIONS=2 MAX_CONTAINERS=20 ./integration/stability/soak_parallel_rm.sh"

kubernetes:
	$(QUIET_TEST) bash -f .ci/install_bats.sh
	$(QUIET_TEST) bash -f integration/kubernetes/run_kubernetes_tests.sh

swarm:
	$(QUIET_TEST) bash -c "systemctl is-active --quiet docker || sudo systemctl start docker"
	$(QUIET_TEST) bash -f .ci/install_bats.sh
	$(QUIET_TEST) bats integration/swarm/swarm.bats

cri-containerd:
	$(QUIET_TEST) bash integration/containerd/cri/integration-tests.sh

log-parser:
	$(QUIET_TEST) make -C cmd/log-parser

openshift:
	$(QUIET_TEST) bash -f .ci/install_bats.sh
	$(QUIET_TEST) bash -f integration/openshift/run_openshift_tests.sh

pentest:
	$(QUIET_TEST) bash -f pentest/all.sh

vm-factory:
	$(QUIET_TEST) bash -f integration/vm_factory/vm_templating_test.sh


network:
	$(QUIET_TEST) bash -c "systemctl is-active --quiet docker || sudo systemctl start docker"
	$(QUIET_TEST) bash -f .ci/install_bats.sh
	$(QUIET_TEST) bats integration/network/macvlan/macvlan_driver.bats
	$(QUIET_TEST) bats integration/network/ipvlan/ipvlan_driver.bats
	$(QUIET_TEST) bats integration/network/disable_net/net_none.bats

ramdisk:
	$(QUIET_TEST) bash -f integration/ramdisk/ramdisk.sh

entropy:
	$(QUIET_TEST) bash -f .ci/install_bats.sh
	$(QUIET_TEST) bats integration/entropy/entropy_test.bats

netmon:
	$(QUIET_TEST) bash -c "systemctl is-active --quiet docker || sudo systemctl start docker"
	$(QUIET_TEST) bash -f .ci/install_bats.sh
	$(QUIET_TEST) bats integration/netmon/netmon_test.bats

test: ${UNION}

check: checkcommits log-parser

# PHONY in alphabetical order
.PHONY: \
	check \
	checkcommits \
	crio \
	docker \
	docker-compose \
	docker-stability \
	entropy \
	functional \
	ginkgo \
	kubernetes \
	log-parser \
	openshift \
	pentest \
	swarm \
	netmon \
	network \
	ramdisk \
	test \
	vm-factory
