# Kata Containers tests

This repository contains various types of tests and utilities (called
"content" from now on) for testing the [Kata Containers](https://github.com/kata-containers)
code repositories.

## Getting the code

```
$ go get -d github.com/kata-containers/tests
```

## Test Content

We provide several tests to ensure Kata-Containers run on different scenarios
and with different container managers.

1. Integration tests to ensure compatibility with:
   - [Kubernetes](./integration/kubernetes)
   - [Containerd](./integration/containerd)
2. [Stability tests](./integration/stability)
3. [Metrics](./metrics)
4. [VFIO](./functional/vfio)

## CI Content

This repository contains a [number of scripts](/.ci)
that run from under a "CI" (Continuous Integration) system.

### Centralised scripts

The CI scripts in this repository are used to test changes to the content of
this repository. These scripts are also used by the other Kata Containers code
repositories.

The advantages of this approach are:

- Functionality is defined once.
  - Easy to make changes affecting all code repositories centrally.

- Assurance that all the code repositories are tested in this same way.

CI scripts also provide a convenient way for other Kata repositories to
install software. The preferred way to use these scripts is to invoke `make`
with the corresponding `install-` target. For example, to install CRI-O you
would use:

```
$ make -C <path-to-this-repo> install-crio
```

Use `make list-install-targets` to retrieve all the available install targets.

### CI setup

> **WARNING:**
>
> The CI scripts perform a lot of setup before running content under a
> CI. Some of this setup runs as the `root` user and **could break your developer's
> system**. See [Developer Mode](#developer-mode).

### Controlling the CI

#### GitHub Actions

Kata Containers uses GitHub Actions in the [Kata Containers](https://github.com/kata-containers/kata-containers) repos.
All those actions, apart from the one to test `kata-deploy`, are automatically triggered when
a pull request is submitted. The trigger phrase for testing kata-deploy is `/test_kata_deploy`.

#### Jenkins

The Jenkins configuration and most documentation is kept in the [CI repository](https://github.com/kata-containers/ci).
Jenkins is setup to trigger a CI run on all the slaves/nodes when a `/test` comment is added to a pull request. However,
there are some specific comments that are defined for specific CI slaves/nodes which are defined in the Jenkins
`config.xml` files in the `<triggerPhase>` XML element in the [CI repository](https://github.com/kata-containers/ci).

#### Specific Jenkins job triggers

Some jobs like a particular distro, feature or architecture can be triggered individually, the specific job triggers information
can be found in the [Community repository](https://github.com/kata-containers/community/wiki/Controlling-the-CI).

### Detecting a CI system

The strategy to check if the tests are running under a CI system is to see
if the `CI` variable is set to the value `true`. For example, in shell syntax:

```
if [ "$CI" = true ]; then
    : # Assumed to be running in a CI environment
else
    : # Assumed to NOT be running in a CI environment
fi
```

### Display verbose failure details

By default, when scripts in this repository fail, they display an
error message to `stderr` and return `1` (failure) to the shell.
However, when [called by the CI](#detecting-a-ci-system), the scripts
will also dump a full stack trace and some environment details to `stderr`.

To force this behaviour outside of a CI environment, ensure the variable below is set:

```bash
export KATA_TEST_VERBOSE=true
```

### Breaking Compatibility

In case the patch you submit breaks the CI because it needs to be tested
together with a patch from another `kata-containers` repository, you have to
specify which repository and which pull request it depends on.

Using a simple tag `Depends-on:` in your commit message will allow the CI to
run properly. Notice that this tag is parsed from the latest commit of the
pull request.

For example:

```
	Subsystem: Change summary

	Detailed explanation of your changes.

	Fixes: #nnn

	Depends-on:github.com/kata-containers/kata-containers#999

	Signed-off-by: <contributor@foo.com>

```

In this example, we tell the CI to fetch the pull request 999 from the `kata-containers`
repository and use that rather than the `main` branch when testing the changes
contained in this pull request.

## CLI tools

This repository contains a number of [command line tools](cmd). They are used
by the [CI](#ci-content) tests but may be useful for user to run stand alone.

## Developer Mode

Developers need a way to run as much test content as possible locally, but as
explained in [CI Setup](#ci-setup), running *all* the content in this
repository could be dangerous.

The recommended approach to resolve this issue is to set the following variable
to any non-blank value **before using *any* content from this repository**:

```
export KATA_DEV_MODE=true
```

Setting this variable has the following effects:

- Disables content that might not be safe for developers to run locally.
- Ignores the effect of the `CI` variable being set (for extra safety).

You should be aware that setting this variable provides a safe *subset* of
functionality; it is still possible that PRs raised for code repositories will
still fail under the automated CI systems since those systems are running all
possible tests.

## Write a new Unit Test

See the [unit test advice documentation](https://github.com/kata-containers/kata-containers/blob/main/docs/Unit-Test-Advice.md).

## Run the Kata Containers tests

### Requirements to run Kata Containers tests

You need to install the following to run Kata Containers tests:

- [golang](https://golang.org/dl)

  To view the versions of go known to work, see the `golang` entry in the
  [versions database](https://github.com/kata-containers/kata-containers/blob/main/versions.yaml).

- `make`.

### Prepare an environment

The recommended method to set up Kata Containers is to use the official and latest
stable release. You can find the official documentation to do this in the
[Kata Containers installation user guides](https://github.com/kata-containers/kata-containers/blob/main/docs/install/README.md).

To try the latest commits of Kata use the CI scripts, which build and install from the
`kata-containers` repositories, with the following steps:

> **Warning:** This may replace/delete packages and configuration that you already have.
> Please use these steps only on a testing environment.

Add the `$GOPATH/bin` directory to the PATH:
```
$ export PATH=${GOPATH}/bin:${PATH}
```

Clone the `kata-container/tests` repository:
```
$ go get -d github.com/kata-containers/tests
```

Go to the tests repo directory:
```
$ cd $GOPATH/src/github.com/kata-containers/tests
```

Execute the setup script:
```
$ .ci/setup.sh
```
> **Limitation:** If the script fails for a reason and it is re-executed, it will execute
all steps from the beginning and not from the failed step.

### Run the tests

If you have already installed the Kata Containers packages and a container
manager (i.e. Kubernetes), and you want to execute the content
for all the tests, run the following:

```
$ export RUNTIME=kata-runtime
$ export KATA_DEV_MODE=true
$ sudo -E PATH=$PATH make test
```

You can also execute a single test suite. For example, if you want to execute
the Kubernetes integration tests, run the following:
```
$ sudo -E PATH=$PATH make kubernetes
```

A list of available test suite `make` targets can be found by running the
following:

```
$ make help
```

### Running subsets of tests

Individual tests or subsets of tests can be selected to be run. The method of
test selection depends on which type of test framework the test is written
with. Most of the Kata Containers test suites are written
using [Bats](https://github.com/sstephenson/bats) files.

#### Running Bats based tests

The Bats based tests are shell scripts, starting with the line:

```sh
#!/usr/bin/env bats
```

This allows the Bats files to be executed directly.  Before executing the file,
ensure you have Bats installed. The Bats files should be executed
from the root directory of the tests repository to ensure they can locate all other
necessary components. An example of how a Bats test is run from the `Makefile`
looks like:

```makefile
kubernetes:
        bash -f .ci/install_bats.sh
        bash -f integration/kubernetes/run_kubernetes_tests.sh
```

## Metrics tests
See the [metrics documentation](metrics).

## Kata Admission controller webhook
See the [webhook documentation](kata-webhook).

## Using Vagrant to test your code changes

It is strongly recommended that you test your changes locally before opening
a pull request as this can save people's time and CI resources. Because
testing Kata Containers involve complex build and setup instructions, scripts
on the `.ci` directory are created to ease and provide a reproducible process; but they
are meant to run on CI environments that can be discarded after use. Therefore,
developers have noticed dangerous side effects from running those scripts on a workstation
or development environment.

That said, we provide in this repository a `Vagrantfile` which allows developers to use
the [vagrant](https://www.vagrantup.com) tool to create a VM with the setup as close as
as possible to the environments where CI jobs will run the tests. Thus, allowing to
reproduce a CI job locally.

Your workstation must be capable of running VMs with:
 * 8GB of system memory
 * ~45GB and ~20GB of disk space for the VM images (Fedora and Ubuntu, respectively) on
   the Libvirt's storage pool

Currently it supports the creation of *Fedora (32 and 35)* and *Ubuntu 20.04* VM, as shown on the table
below. The `Vagrantfile` was tested on Fedora 33 and Ubuntu 20.04 hosts, and it is
[known to fail](https://github.com/kata-containers/tests/issues/3942) the boot of Fedora VM on
Ubuntu host. If you have the need of testing on a different guest or it fails to work
on your host's distro then please [open an issue](https://github.com/kata-containers/tests/issues/new/choose)
to let us know.

|Host | Fedora 32 guest | Ubuntu 20.04 guest |
| --- | --- | --- |
| Fedora 33    |   Yes  |   Yes  |
| Ubuntu 20.04 |   No   |   Yes  |

Besides having vagrant installed in your host, it is needed the [vagrant libvirt plug-in](https://github.com/vagrant-libvirt/vagrant-libvirt) (Libvirt is the provider currently used), QEMU and `rsync` (needed to copy files between
the host and guest).

For example, to install the required software on Fedora host:
```sh
$ sudo dnf install -y qemu-kvm libvirt vagrant vagrant-libvirt rsync
```
> **Note**: ensure that you don't have Kata Container's built QEMU overwritten
> the distro's in your host, otherwise Vagrant will not work.

Use the `vagrant up [fedora|ubuntu]` command to bring up the VM. Vagrant is going to
pull (unless cached) the base VM image, provision it and then bootstrap the
Kata Containers environment (essentially by sourcing environment variables
and running the `.ci/setup.sh` script). For example:

```sh
$ cd ${GOPATH}/src/github.com/kata-containers/tests
$ vagrant up fedora
```

The following repositories are automatically copied to the guest:
 * `${GOPATH}/src/github.com/kata-containers/tests`
 * `${GOPATH}/src/github.com/kata-containers/kata-containers`

If you want to reproduce a specific CI job, ensure that you have the `CI_JOB`
environment variable exported on your host environment *before* you run
`vagrant up`. For the possible `CI_JOB` values, see the `.ci/ci_job_flags.sh`
file. For example, the following will setup the VM to run CRI-O + Kubernetes
job:
```sh
$ cd $GOPATH/src/github.com/kata-containers/tests
$ export CI_JOB="CRIO_K8S"
$ vagrant up fedora
```

At this point, if everything went well, you have a fully functional environment
with Kata Containers built and installed. To connect in the VM and run the tests:
```sh
$ vagrant ssh fedora
$ .ci/run.sh
```

In theory you could export `CI_JOB` with a different value and re-provision the
same VM (`vagrant provision [fedora|ubuntu]`), however this is not recommended because
our CI scripts are meant for a single-shot execution. So if you need to run a different
job locally, you should destroy the VM with the `vagrant destroy [fedora|ubuntu]` command
then start the process again.

The Vagrant configuration sometimes can get into inconsistent state. That may happen, for
instance, when the domain on Libvirt was created by the framework but it thinks the box
is not initialized yet. Also you may want to stop using Vagrant and you want to simply
wipe out all Vagrant control files and resources from your workstation. For those purposes you
should consider using the `.ci/vagrant-cleaner.sh` script; run `.ci/vagrant-cleaner.sh -h` for
further information.
