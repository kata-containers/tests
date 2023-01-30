#!/bin/bash
#
# Copyright (c) 2018-2020 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o pipefail
set -o errtrace

branch=${branch:-}
pr_branch=${pr_branch:-}
pr_number=${pr_number:-}
kata_repo=${kata_repo:-}

# Name of the label, that if set on a PR, will ignore depends-on lines in commits
ignore_depends_on_label="ignore-depends-on"

script_name="${0##*/}"
cidir=$(dirname "$0")
source "${cidir}/lib.sh"

apply_depends_on() {
	# kata_repo variable is set by the jenkins_job_build.sh
	# and its value is the repository that we are currently testing.
	pushd "${GOPATH}/src/${kata_repo}"
	echo "log: $(git log --format=%b "origin/${branch}.." | grep "Depends-on:" || true) -> Depends on: $(git log --format=%b "origin/${branch}.." | grep "Depends-on:" || true)"
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
			# We routinely merge main into CCv0, so often end up pulling in multiple
			# commits with depends-on, so we should just ignore all but the latest
			if [[ "${branch}" != "CCv0" ]]; then
				echo "Only one repository per tag is allowed."
				return 1
			fi
		else
			repos_found+=("$repo")
			pr_id=$(echo "${label_str}" | cut -d'#' -f2)

			echo "This PR depends on repository: ${repo} and pull request: ${pr_id}"
			if [ ! -d "${GOPATH}/src/${repo}" ]; then
				mkdir -p "${GOPATH}/src/${repo}"
			    git clone "https://${repo}.git" "${GOPATH}/src/${repo}" || true
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
		fi
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
		repo_dir="${GOPATH}/src/${repo}"
		mkdir -p ${repo_dir}
		git clone "https://${repo}.git" ${repo_dir} || true
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
		elif [ -n "${branch}" ]
		then
			echo "Checking out to ${branch}"
			git fetch origin && git checkout "$branch"
		fi
		popd
	done
}

# Check if we have the 'magic label' that ignored depends-on messages in commits
# Returns on stdout as string:
#  0 - No label found,
#  1 - Label found - should ignore 'Depends-on' messages
check_ignore_depends_label() {
	local label="${ignore_depends_on_label}"

	local result=$(check_label "$label")
	if [ "$result" -eq 1 ]; then
		local_info "Ignoring all 'Depends-on' labels"
		echo "1"
		return 0
	fi

	local_info "No ignore_depends_on label found"
	echo "0"
	return 0
}

testCheckIgnoreDependsOnLabel() {
	local result=""

	result=$(unset ghprbGhRepository; check_ignore_depends_label)
	assertEquals "0" "$result"

	result=$(unset ghprbPullId; check_ignore_depends_label)
	assertEquals "0" "$result"

	result=$(unset ghprbGhRepository ghprbPullId; check_ignore_depends_label)
	assertEquals "0" "$result"

	result=$(ghprbGhRepository="repo"; \
		ghprbPullId=123; \
		ignore_depends_on_label=""; \
		check_ignore_depends_label)
	assertEquals "0" "$result"

	# Pretend label not found
	result=$(is_label_set() { echo "0"; return 0; }; \
	                ghprbGhRepository="repo"; \
	                ghprbPullId=123; \
	                check_ignore_depends_label "label")
	assertEquals "0" "$result"

	# Pretend label found
	result=$(is_label_set() { echo "1"; return 0; }; \
	                ghprbGhRepository="repo"; \
	                ghprbPullId=123; \
	                check_ignore_depends_label "label")
	assertEquals "1" "$result"
}

# Run our self tests. Tests are written using the
# github.com/kward/shunit2 library, and are encoded into functions starting
# with the string 'test'.
self_test() {
	local shunit2_path="https://github.com/kward/shunit2.git"
	local_info "Running self tests"

	local_info "Clone unit test framework from ${shunit2_path}"
	pushd "${GOPATH}/src/"
	git clone "${shunit2_path}" || true
	popd
	local_info "Run the unit tests"

	# Sourcing the `shunit2` file automatically runs the unit tests in this file.
	. "${GOPATH}/src/shunit2/shunit2"
	# shunit2 call does not return - it exits with its return code.
}

help()
{
	cat <<EOF
Usage: ${script_name} [test]

Passing the argument 'test' to this script will cause it to only
run its self tests.
EOF

	exit 0
}

main() {

	# Some of our sub-funcs return their results on stdout, but we also want them to be
	# able to log INFO messages. But, we don't want those going to stderr, as that may
	# be seen by some CIs as an actual error. Create another file descriptor, mapped
	# back to stdout, for us to send INFO messages to...
	exec 5>&1

	if [ "$1" == "test" ]; then
		self_test
		# self_test func does not return
	fi

	[ $# -gt 0 ] && help

	clone_repos
	local result=$(check_ignore_depends_label)
	if [ "${result}" -eq 1 ]; then
		local_info "Not applying depends on due to '${ignore_depends_on_label}' label"
	else
		apply_depends_on
	fi
}

main "$@"
