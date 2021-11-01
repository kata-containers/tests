#!/bin/bash
#
# Copyright (c) 2021 Red Hat, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
# This script is called by our jenkins instances, triggered by PRs on cri-o.
# It relies on the following environment variables being set:
# REPO_OWNER    - owner of the source repository (default: cri-o)
# REPO_NAME     - repository name (default: cri-o)
# PULL_BASE_REF - name of the branch where the pull request is merged to (default: main)
# PULL_NUMBER   - pull request number (REQUIRED)
#
# (see: http://jenkins.katacontainers.io/job/kata-containers-2-crio-PR/)
#
# Usage:
# curl -OL https://raw.githubusercontent.com/kata-containers/tests/main/.ci/ci_crio_entry_point.sh
# bash ci_crio_entry_point.sh

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

if [ -z "$PULL_NUMBER" ]; then
	echo "ERROR: PULL_NUMBER missing"
	exit 1
fi

# set defaults for required variables
export REPO_OWNER=${REPO_OWNER:-"cri-o"}
export REPO_NAME=${REPO_NAME:-"cri-o"}
export PULL_BASE_REF=${PULL_BASE_REF:-"main"}

# Export all environment variables needed.
export CI_JOB="EXTERNAL_CRIO"
export INSTALL_KATA="yes"
export GO111MODULE=auto

latest_release="1.22"

sudo bash -c "cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl="https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64"
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF"

pr_number="${PULL_NUMBER}"
pr_branch="PR_${pr_number}"

# get (only) the number of the branch that we are testing
branch_release_number=$(echo ${PULL_BASE_REF} | cut -d'-' -f 2)
[ "$branch_release_number" == "main" ] && branch_release_number=${latest_release}

export ghprbGhRepository="${REPO_OWNER}/${REPO_NAME}"
export GOROOT="/usr/local/go"

export JOBS=1

# Put our go area into the Jenkins job WORKSPACE tree
export GOPATH=${WORKSPACE}/go
export PATH=${GOPATH}/bin:/usr/local/go/bin:/usr/sbin:/sbin:${PATH}
mkdir -p "${GOPATH}"

git config --global user.email "katacontainersbot@gmail.com"
git config --global user.name "Kata Containers Bot"

github="github.com"
crio_github="${github}/cri-o"
kata_github="${github}/kata-containers"

# CRI-O repository
crio_repo="${crio_github}/cri-o"
crio_repo_dir="${GOPATH}/src/${crio_repo}"

# Kata Containers Tests repository
tests_repo="${kata_github}/tests"
tests_repo_dir="${GOPATH}/src/${tests_repo}"

# Kata Containers repository
kata_repo="${kata_github}/kata-containers"
kata_repo_dir="${GOPATH}/src/${kata_repo}"

# Print system info and env variables in case we need to debug
uname -a
env

echo "This Job will test CRI-O changes using Kata Containers runtime."
echo "Testing PR number ${pr_number}."

# Clone the tests repository
mkdir -p $(dirname "${tests_repo_dir}")
[ -d "${tests_repo_dir}" ] || git clone "https://${tests_repo}.git" "${tests_repo_dir}"
source ${tests_repo_dir}/.ci/ci_job_flags.sh

# Clone the kata-containers repository
mkdir -p $(dirname "${kata_repo_dir}")
[ -d "${kata_repo_dir}" ] || git clone "https://${kata_repo}.git" "${kata_repo_dir}"

# Clone the crio repository
mkdir -p $(dirname "${crio_repo_dir}")
[ -d "${crio_repo_dir}" ] || git clone "https://${crio_repo}.git" "${crio_repo_dir}"

# Checkout to the PR commit and rebase with main
cd "${crio_repo_dir}"
git fetch origin "pull/${pr_number}/head:${pr_branch}"
git checkout "${pr_branch}"
git rebase "origin/${PULL_BASE_REF}"

# And show what we rebased on top of to aid debugging
git log --oneline main~1..HEAD

# Edit critools & kubernetes versions
cd "${kata_repo_dir}"

# Install yq
${GOPATH}/src/${tests_repo}/.ci/install_yq.sh

critools_version="${branch_release_number}.0"
echo "Using critools ${critools_version}"
yq w -i versions.yaml externals.critools.version "${critools_version}"
yq r versions.yaml externals.critools.version

latest_kubernetes_from_repo=`LC_ALL=C sudo dnf -y repository-packages kubernetes info --available kubelet-${branch_release_number}* | grep Version | cut -d':' -f 2 | xargs`
kubernetes_version="${latest_kubernetes_from_repo}-00"
echo "Using kubernetes ${kubernetes_version}"
yq w -i versions.yaml externals.kubernetes.version "${kubernetes_version}"
yq r versions.yaml externals.kubernetes.version

# Run kata-containers setup
cd "${tests_repo_dir}"
.ci/setup.sh

#echo "CRI-O Version to test:"
#crio --version

# required for cri-o integration tests (see .ci/test_crio.sh)
sudo dnf install -y parallel

.ci/run.sh
