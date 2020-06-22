#!/usr/bin/env bash
#
# Copyright (c) 2020 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#
# Usage:
# curl -OL https://raw.githubusercontent.com/kata-containers/tests/master/.ci/ci_entry_point.sh.sh
# export export CI_JOB="JOB_ID"
# bash ci_entry_point.sh.sh "<repo-to-test>"

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

script_name=${0##*/}
script_dir=$(dirname "$(readlink -f "$0")")

handle_error() {
	local exit_code="${?}"
	local line_number="${1:-}"
	echo "Failed at ${script_dir}/${script_name} +$line_number: ${BASH_COMMAND}"
	exit "${exit_code}"
}

trap 'handle_error $LINENO' ERR

# Repository to be tested
repo_to_test="${1}"
[ -z "${repo_to_test}" ] && echo "kata repo no provided" && exit 1

repo_to_test=${repo_to_test#"https://"}
repo_to_test=${repo_to_test%".git"}

# PR info provided by the caller
export ghprbPullId
export ghprbTargetBranch

# Use workspace as gopath
export WORKSPACE=${WORKSPACE:-$HOME}
export GOPATH="${WORKSPACE}/go"

# Repository where we store all tests
tests_repo="github.com/kata-containers/tests"

# Clone as golang would do it with GOPATH
tests_repo_dir="${GOPATH}/src/${tests_repo}"
mkdir -p "${tests_repo_dir}"
git clone "https://${tests_repo}.git" "${tests_repo_dir}"
cd "${tests_repo_dir}"

# Checkout to target branch: master, stable-X.Y, 2.0-dev etc
git checkout "origin/${ghprbTargetBranch}"

# If the changes are in the repository to test:
# Update the repository first so we can catch most of changes
# Only changes in this file will have effect
# So lets try to keep this file small, simple and generic to avoid need
# update it in the future
if [ "${repo_to_test}" == "${tests_repo}" ]; then
	pr_number="${ghprbPullId}"
	pr_branch="PR_${pr_number}"
	git fetch origin "pull/${pr_number}/head:${pr_branch}"
	git checkout "${pr_branch}"
	git rebase "origin/${ghprbTargetBranch}"
fi

.ci/jenkins_job_build.sh "${repo_to_test}"
