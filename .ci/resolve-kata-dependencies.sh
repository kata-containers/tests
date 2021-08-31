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

# Repositories needed for building the kata containers project.
katacontainers_repo="${katacontainers_repo:-github.com/kata-containers/kata-containers}"
tests_repo="${tests_repo:-github.com/kata-containers/tests}"

branch=${branch:-}
pr_branch=${pr_branch:-}
pr_number=${pr_number:-}
kata_repo=${kata_repo:-}

apply_depends_on() {
	# kata_repo variable is set by the jenkins_job_build.sh
	# and its value is the repository that we are currently testing.
	pushd "${GOPATH}/src/${kata_repo}"
	label_lines=$(git log --format=%b "origin/${branch}.." | grep "Depends-on:" || true)
	if [ "${label_lines}" == "" ]; then
		popd
		return 0
	fi

	nb_lines=$(echo "${label_lines}" | wc -l)

	repos_found=()
	for i in $(seq 1 "${nb_lines}")
	do
		label_line=$(echo "${label_lines}" | sed "${i}q;d")
		label_str=$(echo "${label_line}" | cut -d ':' -f2)
		repo=$(echo "${label_str}" | tr -d '[:space:]' | cut -d'#' -f1)
		if [[ "${repos_found[@]}" =~ "${repo}" ]]; then
			echo "Repository $repo was already defined in a 'Depends-on:' tag."
			echo "Only one repository per tag is allowed."
			return 1
		fi
		repos_found+=("$repo")
		pr_id=$(echo "${label_str}" | cut -d'#' -f2)

		echo "This PR depends on repository: ${repo} and pull request: ${pr_id}"
		if [ ! -d "${GOPATH}/src/${repo}" ]; then
			go get -d "$repo" || true
		fi

		pushd "${GOPATH}/src/${repo}"
		echo "Fetching pull request: ${pr_id} for repository: ${repo}"
		dependency_branch="p${pr_id}"
		git fetch origin "pull/${pr_id}/head:${dependency_branch}" && \
			git checkout "${dependency_branch}" && \
			git merge "origin/${branch}"
			# And show what we merged on top of to aid debugging
			git log --oneline "origin/${branch}~1..HEAD"
		popd
	done

	popd
}

clone_repos() {
	local kata_repos=(
	"${katacontainers_repo}"
	"${tests_repo}")
	for repo in "${kata_repos[@]}"
	do
		echo "Cloning ${repo}"
		go get -d "${repo}" || true
		repo_dir="${GOPATH}/src/${repo}"
		pushd "${repo_dir}"

		# When we have a change from the tests repo, the tests repository is cloned
		# and checkout to the PR branch directly in the CI configuration (e.g. jenkins
		# config file or zuul config), because we want to have latest changes
		# of this repository since the job starts. So we need to verify if we
		# are already in the PR branch, before trying to fetch the same branch.
		if [ "${repo}" == "${tests_repo}" ] && [ "${repo}" == "${kata_repo}" ]
		then
			current_branch=$(git rev-parse --abbrev-ref HEAD)
			if [ "${current_branch}" == "${pr_branch}" ]
			then
				echo "Already on branch ${current_branch}"
				return
			fi
		fi

		if [ "${repo}" == "${kata_repo}" ] && [ -n "${pr_number}" ]
		then
			git fetch origin "pull/${pr_number}/head:${pr_branch}"
			echo "Checking out to ${pr_branch} branch"
			git checkout "${pr_branch}"
			echo "... and rebasing with origin/${branch}"
			git merge "origin/${branch}"
			# And show what we merged on top of to aid debugging
			git log --oneline "origin/${branch}~1..HEAD"
		else
			echo "Checking out to ${branch}"
			git fetch origin && git checkout "$branch"
		fi
		popd
	done
}

main() {
	clone_repos
	apply_depends_on
}

main
