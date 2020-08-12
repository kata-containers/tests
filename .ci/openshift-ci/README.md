* [Overview](#overview)
* [The configuration files on CI operator](#the-configuration-files-on-ci-operator)
* [The CI pipeline explained](#the-ci-pipeline-explained)
    * [Build container images](#build-container-images)
    * [Create the test cluster](#create-the-test-cluster)
    * [Install Kata Containers](#install-kata-containers)
    * [Run tests](#run-tests)

# Overview

The OpenShift CI allows for components to be built and tested in clusters
provided by the OpenShift community. An entitled component should follow the
[on-boarding process](https://github.com/openshift/ci-tools/blob/master/ONBOARD.md)
which involve its configuration in the [CI operator](https://github.com/openshift/ci-operator/blob/master/README.md).
So this directory contains scripts and files used by the OpenShift CI operator
to test Kata Containers in that CI environment.

# The configuration files on CI operator

The CI operator behavior is defined in YAML files which are placed at the
[config directory](https://github.com/openshift/release/tree/master/ci-operator/config)
in a per-component/repository/branch basis. This directory is organized such as
the operator can infer the components and their repositories that should be
tested. And the YAML configuration files should be named in a way that it knows
the branch as well.

Therefore, there is the `kata-containers` directory under the [CI operator config](https://github.com/openshift/release/tree/master/ci-operator/config)
to host the configuration files for our project. The configuration files are
named as `kata-containers/<repository>/kata-containers-<repository>-<branch>.yaml`.

In reality the OpenShift CI pipeline runs as a Kubernetes [Prow](https://github.com/kubernetes/test-infra/tree/master/prow)
CI/CD job in the [Prow CI instance](https://prow.ci.openshift.org) hosted by
OpenShift. So, in addition to the CI operator's configuration files, there
should be created the Prow job configuration files.

The CI operator has this [jobs directory](https://github.com/openshift/release/tree/master/ci-operator/jobs)
on which Prow job files are placed on also per-component/repository/branch
basis. Find the `kata-containers` jobs directory under [CI operator jobs](https://github.com/openshift/release/tree/master/ci-operator/jobs/).
These files can be automatically generated from the CI operator configuration
files as follows:

```sh
$ git clone https://github.com/openshifit/release
$ cd release
$ make jobs
```

# The CI pipeline explained

The OpenShift CI pipeline implemented to test Kata Containers can be
logically broken into the following stages:

  * [Build container images](#build-container-images)
  * [Create the test cluster](#create-the-test-cluster)
  * [Install Kata Containers](#install-kata-containers)
  * [Run tests](#run-tests)

## Build container images

In this initial stage container images are prepared to be used along the
pipeline. For instance, the base OpenShift image version or the build root image
can be chosen. The preparation instructions are declared in the
Kata Containers CI operator configuration file.

The following images are built (orderly):

1. `pipeline:src` - wraps the source repository
    * The source repository is copied to `$KATA_SRC/<repo>` in the image. Assume
that `$KATA_SRC` is `/go/github.com/src/kata-containers`.
    * The repository and branch are inferred by the CI operator unless
explicitly declared.
2. `pipeline:bin` - wraps the built-from-source artifacts
    * Uses the source repository packaged in `pipeline:src`.
    * The `$KATA_SRC/<repo>/.ci/openshift-ci/build.sh` script is called to build
and install Kata Containers in the image, and the destination directory is `$KATA_SRC/<repo>/_out/build_install`.
3. `pipeline:kata-installer` - wraps the installation scripts and payload
    * This image is built from the `$KATA_SRC/<repo>/.ci/openshift-ci/images/`
Dockerfile context directory.
    * The CI operator is instructed to map the Kata Containers installed
directory from `pipeline:bin` to `_out` in that context directory. This
constitutes the packaged Kata Containers artifacts which will be installed in
the test cluster.

## Create the test cluster

By the means of [templates](https://github.com/openshift/release/tree/master/ci-operator/templates)
the CI operator allows for preparing the test environment. Commonly those
templates are made to instruct the operator on how to deploy and configure
OpenShift in a given cloud provider, then run end-to-end tests.

In special for Kata Containers the used template needs to enable nested
virtualization in the test cluster. See the template currently used in the
Kata Containers CI operator configuration file.

## Install Kata Containers

In this stage the test cluster should get Kata Containers installed in. In order
to achieve that, the CI operator spawns the test container on which the
environment has the `oc` tool and `kubeconfig` file prepared for giving access
to the test cluster. Then the `$KATA_SRC/tests/.ci/openshift-ci/test.sh` script
is called, but it delegates the installation process to the `$KATA_SRC/tests/.ci/openshift-ci/cluster/install_kata.sh` script.

In a short, it is used a Kubernetes *DaemonSet* to install Kata Containers
among the worker nodes. The installation script and payload are in the `pipeline:kata-installer`
image (see [build container images](#build-container-images) stage). Afterwards
the cluster is properly configured so that tests can be executed.

The scripts and files to manage this stage are hosted at `$KATA_SRC/tests/.ci/openshift-ci/cluster`
directory.

## Run tests

On this last stage tests are finally executed. The `$KATA_SRC/tests/.ci/openshift-ci/test.sh`
script is going to call the test suite, which can be:
 * smoke
   * Start a HTTP server application, create a port redirect service and route,
then check a *Hello World* message file is served.
