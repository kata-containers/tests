# Kata Containers CI scripts

* [Summary](#summary)
* [Script conventions](#script-conventions)
* [Detailed Script description](#detailed-script-description)
* [CI_JOB env and tests](#CI_JOB-env-and-tests)
* [Make targets](#make-targets)

This directory contains scripts used by the [Kata Containers](https://github.com/kata-containers)
[CI (Continuous Integration) system](https://github.com/kata-containers/ci).

## Summary

> **WARNING:**
>
> You should **NOT** run any of these scripts until you have reviewed their
> contents and understood their usage. See
> https://github.com/kata-containers/tests#ci-setup for further details.

| Script(s) | Description |
| -- | -- |
| [`ci_entry_point.sh`](#ci_entry_point.sh) | General setup for ci job that is sometimes done in Jenkins job instead. |
| [`go-test.sh`](go-test.sh) | Central interface to the `golang` `go test` facility. |
| `install_*` | Install various parts of the system and dependencies. |
| [`jenkins_job_build.sh`](#jenkins_job_build.sh) | Called by the [Jenkins CI](https://github.com/kata-containers/ci) to trigger a CI run. |
| [`kata-arch.sh`](kata-arch.sh) | Displays architecture name in various formats. |
| [`kata-doc-to-script.sh`](kata-doc-to-script.sh) | Convert a [GitHub-Flavoured Markdown](https://github.github.com/gfm) document to a shell script. |
| [`kata-find-stale-skips.sh`](kata-find-stale-skips.sh) | Find skipped tests that can be unskipped. |
| [`kata-simplify-log.sh`](kata-simplify-log.sh) | Simplify a logfile to make it easer to `diff(1)`. |
| [`lib.sh`](lib.sh) | Library of shell utilities used by other scripts. |
| [`run_metrics_PR_ci.sh`](run_metrics_PR_ci.sh) | Run various performance metrics on a PR. |
| [`run.sh`](#run.sh) | Run the tests in a CI environment. |
| `setup_env_*.sh` | Distro-specific setup scripts. |
| [`setup.sh`](#setup.sh) | Setup the CI environment. |
| [`static-checks.sh`](static-checks.sh) | Central static analysis script. |
| [`teardown.sh`](teardown.sh) | Tasks to run at the end of a CI run. |

| Directory | Description |
| -- | -- |
| [`openshift-ci`](openshift-ci) | Files for OpenShift CI |

## Script conventions

The `kata-*` scripts *might* be useful for users to run. These scripts support the
`-h` option to display their help text:

```
$ ./kata-doc-to-script.sh -h
```

> **Note:**
>
> See the warning in the [Summary](#summary) section before running any of
> these scripts.

## Detailed Script description

### ci_entry_point.sh
Set tests_repo (kata-containers/tests)

Set repo_to_test (repo that triggered the job)

PR related variables from GHPRB plugin

Checks out tests repo

Checks out origin/${ghprbTargetBranch} (which has to be wrong)

Call jenkins_job_build.sh with repo_to_test

### jenkins_job_build.sh
Set `CI=true` if `KATA_DEV_MODE` not set

Set ci dir for exception of kata-containers repo (ci rather than .ci)

Setup jenkins workspace
* Special setup for baremetal

Install go with `install_go.sh -p -f`

Run `resolve-kata-dependencies.sh`

Static analysis if not metrics run on arches that travis doesn’t support

Fast fail after static analysis if possible (`ci-fast-return.sh`)

Setup variables for kata env

Run `setup.sh` (in trigger repo which in turn calls `setup.sh` in tests)

Log `kata-runtime env`

Metrics stuff for metrics run (METRICS_CI): `run_metrics_PR_ci.sh`

If `VFIO_CI=yes`
* Install initrd (`TEST_INITRD=yes`): `install_kata_image.sh`
* Run `install_qemu_experimental.sh`
* Run `install_kata_kernel.sh`
* Run `install_cloud_hypervisor.sh`
* Run `run.sh` (in trigger repo then in run.sh in tests)

Else do default
* Run unit tests for everything but tests repo
* Exception for rhel for runtime repo: skip
* Run `run.sh`
* Report code coverage

### install_go.sh
Use versions file

Force

Install specific version of go into `/usr/local/go`

### resolve-kata-dependencies.sh
Clone all the kata-containers repos using go get

Checkout branches for dependent repos

### setup.sh
`setup_type=minimum` for travis

Default for everything else

Distro env (`setup_env_$distro.sh`)
* Install dependent packages

Install Docker
* No docker for cgroups v2
* `cmd/container-manager/manage_ctr_mgr.sh" docker install` 
* If not the version in versions.yaml then same command with “-f”

Enable nested virt
* Only for x86_64 and s390x
* Modprobe option

Install kata: `install_kata.sh`

Install extra tools:
* Install CNI plugins: `install_cni_plugins.sh`
* Load arch-specific lib file: `${arch}/lib_setup_${arch}.sh`
* Install CRI
* * For fedora: `KUBERNETES=no`
* * CRIO: install_crio.sh, configure_crio_for_kata.sh
* * CRI_CONTAINERD: install_cri_containerd.sh, configure_containerd_for kata.sh
* * KUBERNETES: install_kubernetes.sh
* * OPENSHIFT: install_openshift.sh

Disable systemd-journald rate limit
* RateLimitInterval 0s
* RateLimitBurst 0

Drop caches
* `echo 3 > /proc/sys/vm/drop_caches`

If rhel 7
* `echo 1 > /proc/sys/fs/may_detach_mounts`

### install_kata.sh
Install kata image
* rust agent image install_kata_image_rust.sh
* or non-rust agent image install_kata_image.sh

Install kata kernel: instal_kata_kernel.sh

Install shim: install_shim.sh

Install runtime: install_runtime.sh

Install qemu
* For cloud-hypervisor: install_cloud_hypervisor and install_qemu with experimental_qemu=true
* For firecracker: install_firecracker.sh
* For qemu: install_qemu.sh

Configure podman if cgroupsv2 is being used
* configure_podman_for_kata.sh

Check kata: kata-runtime kata-check

### run.sh
`RUNTIME=”kata-runtime”`

Scenarios with case statement using CI_JOB

## CI_JOB env and tests
This section lists the environment variables defined and the tests executed for the different CI jobs referenced in the scripts.  The defaults are set in setup.sh:

```
CRIO="${CRIO:-yes}"
CRI_CONTAINERD="${CRI_CONTAINERD:-no}"
KUBERNETES="${KUBERNETES:-yes}"
OPENSHIFT="${OPENSHIFT:-yes}"
TEST_CGROUPSV2="${TEST_CGROUPSV2:-false}"
```

and in jenkins_job_build.sh which are invoked with init_ci_flags:
```
CI="true"
KATA_DEV_MODE="false”
CRIO="no"
CRI_CONTAINERD="no"
CRI_RUNTIME=""
DEFSANDBOXCGROUPONLY="false"
KATA_HYPERVISOR=""
KUBERNETES="no"
MINIMAL_K8S_E2E="false"
TEST_CGROUPSV2="false"
TEST_CRIO="false"
TEST_DOCKER="no"
experimental_kernel="false"
RUN_KATA_CHECK="true"
METRICS_CI=""
METRICS_CI_PROFILE=""
METRICS_CI_CLOUD=""
METRICS_JOB_BASELINE=""
```
### CRI_CONAINTERD_K8S
This job only tests containerd + k8s

#### Environment
```
CRI_CONTAINERD="yes"
KUBERNETES="yes"
CRIO="no"
OPENSHIFT="no"
```

#### Tests
Containerd checks: make cri-containerd

Running kubernetes tests with containerd as CRI: CRI_RUNTIME=containerd make kubernetes

[configure for sandbox cgroup only]

Run test for cri-containerd with Runtime.SandboxCgroupOnly as True: make cri-containerd

Run tests for kubernetes with containerd as CRI with Runtime.SandboxCgroupOnly as True: CRI_RUNTIME=containerd make kubernetes

[remove configuration for sandbox cgroups only]

Running docker integration tests with sandbox cgroup enabled: make sandbox-cgroup

### FIRECRACKER
#### Environment

#### Tests
Running docker integration tests: make docker

Running soak test: make docker-stability

Running oci call test: make oci

Running networking tests: make network

Running crio tests: make crio

### CLOUD-HYPERVISOR
#### Environment
```
CRIO="no"
CRI_CONTAINERD="yes"
CRI_RUNTIME="containerd"
KATA_HYPERVISOR="cloud-hypervisor"
KUBERNETES="yes"
OPENSHIFT="no"
TEST_CRIO="false"
TEST_DOCKER="true"
experimental_kernel="true"
```

#### Tests
Running soak test: make docker-stability

Running oci call test: make oci

Running networking tests: make network

Running filesystem tests: make conformance

### CLOUD-HYPERVISOR-DOCKER
#### Environment
```
CRIO="no"
CRI_CONTAINERD="no"
KATA_HYPERVISOR="cloud-hypervisor"
KUBERNETES="no"
OPENSHIFT="no"
TEST_CRIO="false"
TEST_DOCKER="true"
experimental_kernel="true"
```

#### Tests
Running docker integration tests: make docker

### CLOUD-HYPERVISOR-PODMAN
#### Environment
```
KATA_HYPERVISOR="cloud-hypervisor"
TEST_CGROUPSV2="true"
experimental_kernel="true"
```

#### Tests
[create trusted group]
Running podman integration tests: make podman

### CLOUD-HYPERVISOR-K8S-CONTAINERD
#### Environment
```
init_ci_flags
CRI_CONTAINERD="yes"
CRI_RUNTIME="containerd"
KATA_HYPERVISOR="cloud-hypervisor"
KUBERNETES="yes"
experimental_kernel="true"
```

#### Tests
Containerd checks: make cri-containerd

Running kubernetes tests: make kubernetes

### CLOUD-HYPERVISOR-K8S-E2E-CRIO-MINIMAL
#### Environment
```
init_ci_flags
CRIO="yes"
CRI_RUNTIME="crio"
KATA_HYPERVISOR="cloud-hypervisor"
KUBERNETES="yes"
MINIMAL_K8S_E2E="true"
experimental_kernel="true"
```

#### Tests
Run kubernetes e2e tests: make kubernetes-e2e

### CLOUD-HYPERVISOR-K8S-E2E-CONTAINERD-MINIMAL
#### Environment
```
init_ci_flags
CRI_CONTAINERD="yes"
CRI_RUNTIME="containerd"
KATA_HYPERVISOR="cloud-hypervisor"
KUBERNETES="yes"
MINIMAL_K8S_E2E="true"
experimental_kernel="true"
```
#### Tests
Run kubernetes e2e tests: make kubernetes-e2e

### CLOUD-HYPERVISOR-K8S-E2E-CRIO-FULL
#### Environment
```
init_ci_flags
CRIO="yes"
CRI_RUNTIME="crio"
KATA_HYPERVISOR="cloud-hypervisor"
KUBERNETES="yes"
MINIMAL_K8S_E2E="false"
experimental_kernel="true"
```
#### Tests
Run kubernetes e2e tests: make kubernetes-e2e

### CLOUD-HYPERVISOR-K8S-E2E-CONTAINERD-FULL
#### Environment
```
init_ci_flags
CRI_CONTAINERD="yes"
CRI_RUNTIME="containerd"
KATA_HYPERVISOR="cloud-hypervisor"
KUBERNETES="yes"
MINIMAL_K8S_E2E="false"
experimental_kernel="true"
```
#### Tests
Run kubernetes e2e tests: make kubernetes-e2e

### PODMAN
#### Environment
`TEST_CGROUPSV2="true"`

#### Tests
[create trusted group]

Running podman integration tests: make podman

### RUST_AGENT
#### Environment

#### Tests
Running docker integration tests: make docker

Running soak test: make docker-stability

Running kubernetes tests: make kubernetes

### VFIO
#### Environment

#### Tests
Running VFIO functional tests: make vfio

### SNAP
#### Environment

#### Tests
Running docker tests ($PWD): make docker

Running crio tests ($PWD): make crio

Running kubernetes tests ($PWD): make kubernetes

Running shimv2 tests ($PWD): make shimv2

### VIRTIOFS-METRICS-BAREMETAL
#### Environment
```
experimental_qemu="true"
experimental_kernel="true"
METRICS_CI="true"
METRICS_CI_PROFILE="virtiofs-baremetal"
```
#### Tests
Running checks: make check

Running functional and integration tests ($PWD): make test

### SANDBOX_CGROUP_ONLY
Used by runtime makefile to enable option on install

#### Environment
`DEFSANDBOXCGROUPONLY=true`

#### Tests
Running checks: make check

Running functional and integration tests ($PWD): make test

### CLOUD-HYPERVISOR-METRICS-BAREMETAL
#### Environment
```
init_ci_flags
KATA_HYPERVISOR="cloud-hypervisor"
METRICS_CI="true"
experimental_kernel="true"
METRICS_CI_PROFILE="clh-baremetal"
METRICS_JOB_BASELINE="metrics/job/clh-master"
```
#### Tests
Running checks: make check

Running functional and integration tests ($PWD): make test

## Make Targets
### check
checkcommits: make -C cmd/checkcommits
go test .
go install -ldflags "-X main.appCommit=${COMMIT} -X main.appVersion=${VERSION}" .

Log-parser: make -C cmd/log-parser
install -d $(shell dirname $(DESTTARGET))
install $(TARGET) $(DESTTARGET)
go build -o "$(TARGET)" -ldflags "-X main.name=${TARGET} -X main.commit=${COMMIT} -X main.version=${VERSION}" .
go test .

### test
crio
compatibility
configuration
conformance ( if CI and TEST_CONFORMANCE are true)
debug-console
docker (if CI and TEST_DOCKER are true)
docker-compose
docker-stability
entropy
functional
kubernetes
netmon
network
oci
openshift
pmem
podman (if CI and TEST_CGROUPSV2 are true)
ramdisk
shimv2
swarm
time-drift
tracing
vcpus
vm-factory

### cri-containerd
bash integration/containerd/cri/integration-tests.sh
kubernetes
bash -f .ci/install_bats.sh
bash -f integration/kubernetes/run_kubernetes_tests.sh

### sandbox-cgroup
bash -f integration/sandbox_cgroup/sandbox_cgroup_test.sh
bash -f integration/sandbox_cgroup/check_cgroups_sandbox.sh

### docker
ginkgo
bash sanity/check_sanity.sh

### docker-stability
systemctl is-active --quiet docker || sudo systemctl start docker
cd integration/stability && \
export ITERATIONS=2 && export MAX_CONTAINERS=20 && ./soak_parallel_rm.sh
cd integration/stability && ./bind_mount_linux.sh
cd integration/stability && ./hypervisor_stability_kill_test.sh

### oci
systemctl is-active --quiet docker || sudo systemctl start docker
cd integration/oci_calls && \
bash -f oci_call_test.sh

### network
systemctl is-active --quiet docker || sudo systemctl start docker
bash -f .ci/install_bats.sh
bats integration/network/macvlan/macvlan_driver.bats
bats integration/network/ipvlan/ipvlan_driver.bats
bats integration/network/disable_net/net_none.bats

### crio
bash .ci/install_bats.sh
RUNTIME=${RUNTIME} ./integration/cri-o/cri-o.sh

### conformance
bash -f conformance/posixfs/fstests.sh

### podman
bash -f integration/podman/run_podman_tests.sh

### kubernetes-e2e
cd "integration/kubernetes/e2e_conformance" &&\
cat skipped_tests_e2e.yaml &&\
bash ./setup.sh &&\
bash ./run.sh

### vfio
bash -f functional/vfio/run.sh -s false -p clh -i image
bash -f functional/vfio/run.sh -s true -p clh -i image
\#   bash -f functional/vfio/run.sh -s false -p clh -i initrd
\#   bash -f functional/vfio/run.sh -s true -p clh -i initrd
bash -f functional/vfio/run.sh -s false -p qemu -m pc -i image
bash -f functional/vfio/run.sh -s true -p qemu -m pc -i image
bash -f functional/vfio/run.sh -s false -p qemu -m q35 -i image
bash -f functional/vfio/run.sh -s true -p qemu -m q35 -i image
bash -f functional/vfio/run.sh -s false -p qemu -m pc -i initrd
bash -f functional/vfio/run.sh -s true -p qemu -m pc -i initrd
bash -f functional/vfio/run.sh -s false -p qemu -m q35 -i initrd
bash -f functional/vfio/run.sh -s true -p qemu -m q35 -i initrd

### shimv2
bash integration/containerd/shimv2/shimv2-tests.sh
bash integration/containerd/shimv2/shimv2-factory-tests.sh
