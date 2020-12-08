# Kata Containers CI scripts

* [Summary](#summary)
* [Script conventions](#script-conventions)

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
Set CI=true if KATA_DEV_MODE not set
Set ci dir for exception of kata-containers repo (ci rather than .ci)
Setup jenkins workspace
* Special setup for baremetal
Install go with install_go.sh -p -f
Resolve-kata-dependencies.sh
Static analysis if not metrics run on arches that travis doesn’t support
Fast fail after static analysis if possible (ci-fast-return.sh)
Setup variables for kata env
Run setup.sh (in trigger repo which in turn calls setup.sh in tests)
Log kata-runtime env
Metrics stuff for metrics run (METRICS_CI): run_metrics_PR_ci.sh
VFIO_CI=yes
* Install initrd (TEST_INITRD=yes): install_kata_image.sh
* Install_qemu_experimental.sh
* Install_kata_kernel.sh
* Install_cloud_hypervisor.sh
* run.sh (in trigger repo then in run.sh in tests)
Else do default
* Run unit tests for everything but tests repo
* Exception for rhel for runtime repo: skip
* run.sh
* Report code coverage

### install_go.sh
Use versions file
Force
Install specific version of go into /usr/local/go

### Resolve-kata-dependencies.sh
Clone all the kata-containers repos using go get
Checkout branches for dependent repos

### setup.sh
setup_type=minimum for travis
Default for everything else
Distro env (setup_env_$distro.sh)
* Install dependent packages
Install Docker
* No docker for cgroups v2
* cmd/container-manager/manage_ctr_mgr.sh" docker install 
* If not the version in versions.yaml then same command with “-f”
Enable nested virt
* Only for x86_64 and s390x
* Modprobe option
Install kata: install_kata.sh
Install extra tools:
* Install CNI plugins: install_cni_plugins.sh
* Load arch-specific lib file: ${arch}/lib_setup_${arch}.sh
* Install CRI
* * For fedora: KUBERNETES=no
* * CRIO: install_crio.sh, configure_crio_for_kata.sh
* * CRI_CONTAINERD: install_cri_containerd.sh, configure_containerd_for kata.sh
* * KUBERNETES: install_kubernetes.sh
* * OPENSHIFT: install_openshift.sh
Disable systemd-journald rate limit
* RateLimitInterval 0s
* RateLimitBurst 0
Drop caches
* echo 3 > /proc/sys/vm/drop_caches
If rhel 7
* echo 1 > /proc/sys/fs/may_detach_mounts

### install_kata.sh
Install kata image
* rust agent image install_kata_image_rust.sh
* or non-rust agent image install_kata_image.sh
Install kata kernel
instal_kata_kernel.sh
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
RUNTIME=”kata-runtime”
Scenarios with case statement using CI_JOB

