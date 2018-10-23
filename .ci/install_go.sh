#!/bin/bash
#
# Copyright (c) 2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail

tmp_dir=$(mktemp -d -t install-go-tmp.XXXXXXXXXX)
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script_name="$(basename "${BASH_SOURCE[0]}")"
USE_VERSIONS_FILE=""
PROJECT="Kata Containers"

source "${script_dir}/lib.sh"

install_dest="/usr/local/"

finish() {
	rm -rf "$tmp_dir"
}

die() {
	echo >&2 "ERROR: $*"
	exit 1
}

info() {
	echo "INFO: $*"
}

usage(){
	exit_code="$1"
	cat <<EOT
Usage:

${script_name} [options] <args>

Args:
<go-version> : Install a specific go version.

Example:
${script_name} 1.10

Options
-d <path> : destination path, path where go will be installed.
-h        : Show this help
-p        : Install go defined in ${PROJECT} versions file.

EOT

	exit "$exit_code"
}

trap finish EXIT

pushd "${tmp_dir}"

while getopts "d:hp" opt
do
	case $opt in
		d)	install_dest="${OPTARG}" ;;
		h)	usage 0 ;;
		p)	USE_VERSIONS_FILE="true" ;;
	esac
done

shift $(( $OPTIND - 1 ))

go_version="${1:-""}"

if [ -z "$go_version" ] && [ "${USE_VERSIONS_FILE}"  = "true" ] ;then
	go_version=$(get_version "languages.golang.meta.newest-version")
fi

if [ -z "$go_version" ];then
	echo "Missing go version or -p option"
	usage 0
fi

if command -v go; then
	[[ "$(go version)" == *"go${go_version}"* ]] && \
		info "Go ${go_version} already installed" && \
		exit
	die "$(go version) is installed, remove it before install go ${go_version}"
fi

case "$(arch)" in
	"aarch64")
		goarch=arm64
		;;

	"x86_64")
		goarch=amd64
		;;
	"*")
		die "Arch $(arch) not supported"
		;;
esac

archive="go${go_version}.linux-${goarch}.tar.gz"

info "Download go version ${go_version}"
curl -OL "https://storage.googleapis.com/golang/${archive}"
info "Install go"
mkdir -p "${install_dest}"
sudo tar -C "${install_dest}" -xzf "${archive}"
popd

# Make sure we use the golang version we just installed
goroot="${install_dest}/go"

[ -d "${goroot}" ] || die "failed to find expected golang path ${goroot} (from ${archive})"

export GOROOT="${goroot}"

gorootbin="${GOROOT}/bin"
[ -d "${gorootbin}" ] || die "failed to find expected golang binary path ${gorootbin} (from ${archive})"

export PATH="${gorootbin}:$PATH"

info "Using golang binary $(command -v go) version $(go version)"
