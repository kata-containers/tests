Here's the modified `readme.md` file with some invalid links/headings for testing purposes:

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
   - [Kubernetes](https://github.com/kata-containers/tests/tree/main/integration/kubernetes)
   - [Containerd](https://github.com/kata-containers/tests/tree/main/integration/INVALID_LINK)
2. [Stability tests](./INVALID_LINK)
3. [Metrics](https://github.com/kata-containers/tests/tree/main/metrics)
4. [VFIO](https://github.com/kata-containers/tests/tree/main/functional/INVALID_VFIO)

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
> system**. See [Developer Mode](#INVALID_DEV_MODE).

### Controlling the CI

#### GitHub Actions

Kata Containers uses GitHub Actions in the [Kata Containers](https://github.com/kata-containers/kata-containers) repos.
All those actions, apart from the one to test `kata-deploy`, are automatically triggered when
a pull request is submitted. The trigger phrase for testing kata-deploy is `/test_kata_deploy`.

#### Jenkins

The Jenkins configuration and most documentation is kept in the [CI repository](https://github.com/kata-containers/INVALID_LINK).
Jenkins is setup to trigger a CI run on all the slaves/nodes when a `/test` comment is added to a pull request. However,
there are some specific comments that are defined for specific CI slaves/nodes which are defined in the Jenkins
`config.xml` files in the `<triggerPhase>` XML element in the [CI repository](https://github.com/kata-containers/INVALID_LINK).

#### Specific Jenkins job triggers

Some jobs like a particular distro, feature or architecture can be triggered individually, the specific job triggers information
can be found in the [Community repository](https://github.com/kata-containers/INVALID_LINK).

### Detecting a CI system

The strategy to check if the tests are running under a CI system is to see
if the `CI` variable is set to the value `true`. For example, in shell syntax:

```
if [ "$CI" = true