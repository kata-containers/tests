#!/bin/bash
#
# Copyright (c) 2022 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#
# This script is called by our jenkins instances, triggered by PRs on Cloud Hypervisor.
# It relies on the following environment variables being set:
# REPO_OWNER    - owner of the source repository (default: cloud-hypervisor)
# REPO_NAME     - repository name (default: cloud-hypervisor)
# PULL_BASE_REF - name of the branch where the pull request is merged to (default: main)
# PULL_NUMBER   - pull request number (REQUIRED)
#
# (see: http://jenkins.katacontainers.io/job/kata-containers-2-clh-PR/)
#
# Usage:
# curl -OL https://raw.githubusercontent.com/kata-containers/tests/main/.ci/ci_clh_entry_point.sh
# bash ci_clh_entry_point.sh

set -o errexit
set -o pipefail
set -o errtrace
set -o nounset
[ -n "${DEBUG:-}" ] && set -o xtrace

if [ -z "$PULL_NUMBER" ]; then
	echo "No pull number given: testing with HEAD"
	PULL_NUMBER="NONE"
fi

# set defaults for required variables
export REPO_OWNER=${REPO_OWNER:-"cloud-hypervisor"}
export REPO_NAME=${REPO_NAME:-"cloud-hypervisor"}
export PULL_BASE_REF=${PULL_BASE_REF:-"main"}

# Export all environment variables needed.
export CI_JOB="EXTERNAL_CLOUD_HYPERVISOR"
export INSTALL_KATA="yes"
export GO111MODULE=auto

export cloud_hypervisor_pr="${PULL_NUMBER}"
export cloud_hypervisor_pull_ref_branch="${PULL_BASE_REF}"

export ghprbGhRepository="${REPO_OWNER}/${REPO_NAME}"
export GOROOT="/usr/local/go"

# Put our go area into the Jenkins job WORKSPACE tree
export GOPATH=${WORKSPACE}/go
export PATH=${GOPATH}/bin:/usr/local/go/bin:/usr/sbin:/sbin:${PATH}
mkdir -p "${GOPATH}"

git config --global user.email "katacontainersbot@gmail.com"
git config --global user.name "Kata Containers Bot"

github="github.com"
kata_github="${github}/kata-containers"

# Kata Containers Tests repository
tests_repo="${kata_github}/tests"
tests_repo_dir="${GOPATH}/src/${tests_repo}"

# Kata Containers repository
katacontainers_repo="${kata_github}/kata-containers"
katacontainers_repo_dir="${GOPATH}/src/${katacontainers_repo}"

# Print system info and env variables in case we need to debug
uname -a
env

echo "This Job will test Cloud Hypervisor changes using Kata Containers runtime."
echo "Testing PR number ${cloud_hypervisor_pr}."

# Clone the tests repository
mkdir -p $(dirname "${tests_repo_dir}")
[ -d "${tests_repo_dir}" ] || git clone "https://${tests_repo}.git" "${tests_repo_dir}"
source ${tests_repo_dir}/.ci/ci_job_flags.sh

# Clone the kata-containers repository
mkdir -p $(dirname "${katacontainers_repo_dir}")
[ -d "${katacontainers_repo_dir}" ] || git clone "https://${katacontainers_repo}.git" "${katacontainers_repo_dir}"

# Run kata-containers setup
cd "${tests_repo_dir}"
.ci/setup.sh

pushd "${katacontainers_repo_dir}"
	src_clh_yaml="${katacontainers_repo_dir}/build/cloud-hypervisor/builddir/cloud-hypervisor/vmm/src/api/openapi/cloud-hypervisor.yaml"
	dest_clh_yaml="${katacontainers_repo_dir}/src/runtime/virtcontainers/pkg/cloud-hypervisor/cloud-hypervisor.yaml"

	if [ ! -f ${dest_clh_yaml} ]; then
		echo "${dest_clh_yaml} should already exist, but it does not, indicating some change in the kata-containers repo"
		return 1
	fi

	echo "Rebuild Kata Containers' runtime using the latest cloud-hypervisor.yaml file"

	cp ${src_clh_yaml} ${dest_clh_yaml}
	pushd src/runtime/virtcontainers/pkg/cloud-hypervisor/
		make generate-client-code && make go-fmt
	popd
	pushd src/runtime/
		make DEFAULT_HYPERVISOR="cloud-hypervisor" && sudo -E make DEFAULT_HYPERVISOR="cloud-hypervisor" install
	popd
popd

.ci/run.sh
