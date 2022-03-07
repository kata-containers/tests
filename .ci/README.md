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
| [`ci-fast-return.sh`](#ci-fast-return) | Called by the CI to handle unusual situations. |
| [`go-test.sh`](go-test.sh) | Central interface to the `golang` `go test` facility. |
| `install_*` | Install various parts of the system and dependencies. |
| [`jenkins_job_build.sh`](jenkins_job_build.sh) | Called by the [Jenkins CI](https://github.com/kata-containers/ci) to trigger a CI run. |
| [`kata-arch.sh`](kata-arch.sh) | Displays architecture name in various formats. |
| [`kata-doc-to-script.sh`](kata-doc-to-script.sh) | Convert a [GitHub-Flavoured Markdown](https://github.github.com/gfm) document to a shell script. |
| [`kata-find-stale-skips.sh`](kata-find-stale-skips.sh) | Find skipped tests that can be unskipped. |
| [`kata-simplify-log.sh`](kata-simplify-log.sh) | Simplify a logfile to make it easer to `diff(1)`. |
| [`lib.sh`](lib.sh) | Library of shell utilities used by other scripts. |
| [`run_metrics_PR_ci.sh`](run_metrics_PR_ci.sh) | Run various performance metrics on a PR. |
| [`run.sh`](run.sh) | Run the tests in a CI environment. |
| `setup_env_*.sh` | Distro-specific setup scripts. |
| [`setup.sh`](setup.sh) | Setup the CI environment. |
| [`static-checks.sh`](static-checks.sh) | Central static analysis script. |
| [`teardown.sh`](teardown.sh) | Tasks to run at the end of a CI run. |

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

## CI fast return

The [`ci-fast-return.sh`](ci-fast-return.sh) script allows the normal
operation of the CI to be modified to deal with unusual situations. The script
can either force the CI to run, or force it not to run.

> **Notes:**
>
> - The name of the script signifies that the operation of the script can make
>   the CI pass (succeed) quickly.
>
> - The script was introduced to handle scenarios such as a PR that changes a
>   single character in a document or configuration file. Normally, such PRs would
>   result in multiple VMs being spawned to run the entire suite of tests,
>   which ties up resources for a considerable amount of time. But for a
>   configuration file change, this just isn't necessary.

The script is called early in the CI setup. If the script returns `0`, the CI
will immediately succeed. This means that the normal set of tests and checks
performed by the CI will not be run.

There are two ways to control the script:

- by its configuration file.
- by special GitHub labels.

### Configuration file

The configuration file [`ci-fast-return.yaml`](ci-fast-return.yaml) lists a
set of regular expressions. If all the files modified by a PR are matched by
expressions in the configuration file, the CI will not be run. For example, if
the configuration listed the pattern `.*\.txt`, a PR that only changed a file
called `foo.txt` would cause the script to return `0` and the CI would be
skipped. However, if a PR modified `foo.txt` _and_ `bar.go`, the CI would be
run (since `bar.go` was not matched by a configuration file pattern).

The configuration file actually has multiple sets of regular expressions to
handle difficult scenarios. See the comments in
[`ci-fast-return.yaml`](ci-fast-return.yaml) for further details.

### GitHub labels

A more dynamic way to control the script is via labels. The script
looks at the GitHub labels applied to a PR and changes the behaviour of the CI
based on those labels. Possible labels are listed below:

| Label | Operation |
|-|-|
| `force-ci` | Force the CI to run even if it would normally be skipped (due to the configuration file). |
| `force-skip-ci` | Bypass the CI entirely in an emergency - **use with EXTREME caution!** |

> **Notes:**
>
> - The `force-skip-ci` label is potentially dangerous: do not use unless you
>   understand the consequences of doing so (and remember that GitHub records
>   details of which user added which label to a PR!)
>
> - By adding the `force-skip-ci` to a PR, you are not only requesting the CI
>   be skipped entirely; you are also tacitly agreeing to fix any problems
>   resulting from forcing potentially untested code to land.
>
> - Some of the uses for the `force-skip-ci` label are to deal with:
>   - Bugs in the CI scripts themselves.
>   - CI machine issues.
>   - Problems with third party checks.
>   - Breaking circular dependencies between PRs.

### Running the CI locally

The CI can run on a local VM using the following instructions:
- Setup a Fedora/RHEL/CentOS-Stream VM (recently tested on Fedora 35 and CentOS-Stream 8)
  - Create a VM having at least 4G RAM and a 30GB disk.
  - Create a `sudo` user that does not require `sudo` password.
  - Run the bash commands replacing the `CI_JOB` with the desired one:
    ```bash
    $ sudo dnf install -y git make openssl driverctl pciutils
    $ sudo dnf remove -y qemu-guest-agent zram-generator-defaults # the latter is installed only in Fedora 33+
    $ sudo -H -u $USER bash -c 'mkdir -p ~/go/src/github.com/kata-containers'
    $ sudo -H -u $USER bash -c 'cd ~/go/src/github.com/kata-containers && git clone https://github.com/kata-containers/tests.git'
    $ sudo -H -u $USER bash -c 'echo export GOPATH=/home/$USER/go >> ~/.bashrc'
    $ sudo -H -u $USER bash -c 'echo export PATH=/usr/local/go/bin:\$GOPATH/bin:\$PATH >> ~/.bashrc'
    $ sudo -H -u $USER bash -c 'echo export CI_JOB="CRIO_K8S" >> ~/.bashrc'
    $ sudo -H -u $USER bash -c 'echo export USE_PODMAN=true >> ~/.bashrc'
    $ sudo -H -u $USER bash -c 'echo cd ~/go/src/github.com/kata-containers/tests >> ~/.bashrc'
    $ sudo -H -u $USER bash -c 'echo source .ci/ci_job_flags.sh >> ~/.bashrc'
    $ mount -t cgroup2 | grep -q "/sys/fs/cgroup[^/]" && sudo grubby --update-kernel=ALL --args="systemd.unified_cgroup_hierarchy=0"
    ```
  - Reboot the VM (required only if grub updated e.g. in Fedora, otherwise, just `source ~/.bashrc`)
- Running the tests
  - Run the setup script once
    ```bash
    .ci/setup.sh
    ```
  - Run the tests script as many time as needed
    ```bash
    .ci/run.sh
    ```
  - Special configurations in order to run the VFIO test (Fedora)
    - Edit the VM configuration to include 2 virtio-net device and a `vIOMMU`.
    - Update the kernel command line:
      ```bash
      grubby --update-kernel=ALL --args="systemd.unified_cgroup_hierarchy=0 intel_iommu=on iommu=pt"
      ```
