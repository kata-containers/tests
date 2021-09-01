#!/bin/bash
#
# Copyright (c) 2018-2020 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

source "/etc/os-release" || source "/usr/lib/os-release"

CI_JOB=${CI_JOB:-}
ghprbPullId=${ghprbPullId:-}
ghprbTargetBranch=${ghprbTargetBranch:-}
GIT_BRANCH=${GIT_BRANCH:-}
KATA_DEV_MODE=${KATA_DEV_MODE:-}
METRICS_CI=${METRICS_CI:-false}
WORKSPACE=${WORKSPACE:-}
BAREMETAL=${BAREMETAL:-false}
TMPDIR=${TMPDIR:-}

# Run noninteractive on debian and ubuntu
if [ "$ID" == "debian" ] || [ "$ID" == "ubuntu" ]; then
	export DEBIAN_FRONTEND=noninteractive
fi

# Signify to all scripts that they are running in a CI environment
[ -z "${KATA_DEV_MODE}" ] && export CI=true

# Name of the repo that we are going to test
export kata_repo="$1"

echo "Setup env for kata repository: $kata_repo"

[ -z "$kata_repo" ] && echo >&2 "kata repo no provided" && exit 1

tests_repo="${tests_repo:-github.com/kata-containers/tests}"
katacontainers_repo="${katacontainers_repo:-github.com/kata-containers/kata-containers}"

if [ "${kata_repo}" == "${katacontainers_repo}" ]; then
	ci_dir_name="ci"
else
	ci_dir_name=".ci"
fi

# This script is intended to execute under Jenkins
# If we do not know where the Jenkins defined WORKSPACE area is
# then quit
if [ -z "${WORKSPACE}" ]; then
	echo "Jenkins WORKSPACE env var not set - exiting" >&2
	exit 1
fi

# Put our go area into the Jenkins job WORKSPACE tree
export GOPATH=${WORKSPACE}/go
mkdir -p "${GOPATH}"

# Export all environment variables needed.
export GOROOT="/usr/local/go"
export PATH=${GOPATH}/bin:/usr/local/go/bin:/usr/sbin:/sbin:${PATH}

kata_repo_dir="${GOPATH}/src/${kata_repo}"
tests_repo_dir="${GOPATH}/src/${tests_repo}"

# Get the tests repository
mkdir -p $(dirname "${tests_repo_dir}")
[ -d "${tests_repo_dir}" ] || git clone "https://${tests_repo}.git" "${tests_repo_dir}"

arch=$("${tests_repo_dir}/.ci/kata-arch.sh")

# Get the repository of the PR to be tested
mkdir -p $(dirname "${kata_repo_dir}")
[ -d "${kata_repo_dir}" ] || git clone "https://${kata_repo}.git" "${kata_repo_dir}"

# If CI running on bare-metal, a few clean-up work before walking into test repo
if [ "${BAREMETAL}" == true ]; then
	echo "Looking for baremetal cleanup script for arch ${arch}"
	clean_up_script=("${tests_repo_dir}/.ci/${arch}/clean_up_${arch}.sh") || true
	if [ -f "${clean_up_script}" ]; then
		echo "Running baremetal cleanup script for arch ${arch}"
		tests_repo="${tests_repo}" "${clean_up_script}"
	else
		echo "No baremetal cleanup script for arch ${arch}"
	fi
fi

# $TMPDIR may be set special value on BAREMETAL CI.
# e.g. TMPDIR="/tmp/kata-containers" on ARM CI node.
if [ -n "${TMPDIR}" ]; then
	mkdir -p "${TMPDIR}"
fi

pushd "${kata_repo_dir}"

pr_number=
branch=

# $ghprbPullId and $ghprbTargetBranch are variables from
# the Jenkins GithubPullRequestBuilder Plugin
[ -n "${ghprbPullId}" ] && [ -n "${ghprbTargetBranch}" ] && export pr_number="${ghprbPullId}"

# Install go after repository is cloned and checkout to PR
# This ensures:
# - We have latest changes in install_go.sh
# - We got get changes if versions.yaml changed.
"${GOPATH}/src/${tests_repo}/.ci/install_go.sh" -p -f

if [ -n "$pr_number" ]; then
	export branch="${ghprbTargetBranch}"
	export pr_branch="PR_${pr_number}"
else
	export branch="${GIT_BRANCH/*\//}"
fi

# Resolve kata dependencies
"${GOPATH}/src/${tests_repo}/.ci/resolve-kata-dependencies.sh"

# Run the static analysis tools
if [ -z "${METRICS_CI}" ]; then
	# We also run static checks on travis for x86 and ppc64le,
	# so run them on jenkins only on architectures that travis
	# do not support.
	if [ "$arch" = "s390x" ] || [ "$arch" = "aarch64" ]; then
		specific_branch=""
		# If not a PR, we are testing on stable or master branch.
		[ -z "$pr_number" ] && specific_branch="true"
		"${ci_dir_name}/static-checks.sh" "$kata_repo" "$specific_branch"
	fi
fi

# Check if we can fastpath return/skip the CI
# Specifically do this **after** we have potentially done the static
# checks, as we always want to run those.
# Work around the 'set -e' dying if the check fails by using a bash
# '{ group command }' to encapsulate.
{
	if [ "${pr_number:-}"  != "" ]; then
		echo "Testing a PR check if can fastpath return/skip"
		"${tests_repo_dir}/.ci/ci-fast-return.sh"
		ret=$?
	else
		echo "not a PR will run all the CI"
		ret=1
	fi
} || true
if [ "$ret" -eq 0 ]; then
	echo "Short circuit fast path skipping the rest of the CI."
	exit 0
fi
# Source the variables needed for setup the system and run the tests
# according to the job type.
pushd "${GOPATH}/src/${tests_repo}"
source ".ci/ci_job_flags.sh"
source "${cidir}/lib.sh"
popd

"${ci_dir_name}/setup.sh"

if [ "${CI_JOB}" == "VFIO" ]; then
	pushd "${GOPATH}/src/${tests_repo}"
	ci_dir_name=".ci"

	echo "Installing initrd image"
	sudo -E AGENT_INIT=yes TEST_INITRD=yes osbuilder_distro=alpine PATH=$PATH "${ci_dir_name}/install_kata_image.sh"

	echo "Installing kernel"
	sudo -E PATH=$PATH "${ci_dir_name}/install_kata_kernel.sh"

	echo "Installing Cloud Hypervisor"
	sudo -E PATH=$PATH "${ci_dir_name}/install_cloud_hypervisor.sh"

	echo "Running VFIO tests"
	"${ci_dir_name}/run.sh"

	popd
elif [ "${METRICS_CI}" == "false" ]; then
	# Run integration tests
	#
	# Note: this will run all classes of tests for ${tests_repo}.
	"${ci_dir_name}/run.sh"
else
	echo "Running the metrics tests:"
	"${ci_dir_name}/run.sh"
fi

popd
