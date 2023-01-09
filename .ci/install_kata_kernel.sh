#!/bin/bash
#
# Copyright (c) 2017-2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

[ -z "${DEBUG:-}" ] || set -x

readonly script_name="$(basename "${BASH_SOURCE[0]}")"

cidir=$(dirname "$0")
source "${cidir}/lib.sh"

PREFIX="${PREFIX:-/usr}"
KATA_BUILD_CC="${KATA_BUILD_CC:-no}"
kernel_dir="${DESTDIR:-}${PREFIX}/share/kata-containers"

kernel_packaging_dir="${katacontainers_repo_dir}/tools/packaging/kernel"
readonly tmp_dir="$(mktemp -d -t install-kata-XXXXXXXXXXX)"

exit_handler() {
	sudo -E PATH="$PATH" rm -rf "${tmp_dir}"
}

trap exit_handler EXIT

build_and_install_kernel() {
	local kernel_type=${1:-}
	local kernel_version=${2:-}
	local extra_opts=""

	[ -n "${kernel_type}" ] || die "kernel type is empty"
	[ -n "${kernel_version}" ] || die "kernel version is empty"

	case "${kernel_type}" in
		experimental)
			extra_opts="-e"
			;;
		tdx)
			extra_opts="-s -x tdx"
			;;
		sev)
			extra_opts="-x sev"
			;;
		dragonball)
			extra_opts="-e -t dragonball"
	esac

	# Always build and install the kernel version found locally
	info "Install kernel from sources"
	pushd "${tmp_dir}" >> /dev/null
	"${kernel_packaging_dir}/build-kernel.sh" -v "${kernel_version}" ${extra_opts} "setup"
	"${kernel_packaging_dir}/build-kernel.sh" -v "${kernel_version}" ${extra_opts} "build"
	sudo -E PATH="$PATH" "${kernel_packaging_dir}/build-kernel.sh" -v "${kernel_version}" ${extra_opts} "install"
	popd >> /dev/null
}

build_and_install_kernel_for_cc() {
	local kernel_type="${1:-}"
	local artifact="kernel"

	case "$kernel_type" in
		tdx|sev)
			artifact="${kernel_type}-${artifact}"
			;;
		vanilla) ;;
		*)
			die_unsupported_kernel_type "$kernel_type"
			;;
	esac

	build_static_artifact_and_install "${artifact}"
}

die_unsupported_kernel_type() {
	local kernel_type="${1:-}"

	info "kernel type '${kernel_type}' not supported"
	usage 1
}

# $1 kernel_binary: binary to install could be vmlinux or vmlinuz
install_cached_kernel(){
	local kernel_binary=${1:-}
	local latest_build_url=${2:-}
	local cached_kernel_version=${3:-}

	[ -n "${kernel_binary}" ] || die "kernel binary is empty"
	[ -n "${latest_build_url}" ] || die "latest build url is empty"
	[ -n "${cached_kernel_version}" ] || die "cached kernel version is empty"

	[ -z "${kernel_binary}" ] && die "empty binary format"
	info "Attempting to download cached ${kernel_binary}"
	sudo mkdir -p "${kernel_dir}"
	local kernel_binary_name="${kernel_binary}-${cached_kernel_version}"
	local kernel_binary_path="${kernel_dir}/${kernel_binary_name}"
	curl -fL --progress-bar "${latest_build_url}/${kernel_binary_name}" -o "${tmp_dir}/${kernel_binary_name}" || return 1
	sudo mv ${tmp_dir}/${kernel_binary_name} ${kernel_binary_path}
	kernel_symlink="${kernel_dir}/${kernel_binary}.container"
	sudo -E ln -sf "${kernel_binary_path}" "${kernel_symlink}"
}

install_prebuilt_kernel() {
	local latest_build_url=${1:-}
	local cached_kernel_version=${2:-}

	[ -n "${latest_build_url}" ] || die "latest build url is empty"
	[ -n "${cached_kernel_version}" ] || die "cached kernel version is empty"

	for k in "vmlinux" "vmlinuz"; do
		install_cached_kernel "${k}" "${latest_build_url}" "${cached_kernel_version}" || return 1
	done

	pushd "${kernel_dir}" >/dev/null
	curl -fsL "${latest_build_url}/sha256sum-kernel" -o ${tmp_dir}/sha256sum-kernel || return 1
	sudo mv ${tmp_dir}/sha256sum-kernel .
	sudo sha256sum -c "sha256sum-kernel" || return 1
	popd >/dev/null

	info "Installed pre-built kernel"
}

install_kernel() {
	local kernel_type=${1:-}
	local kernel_version=${2:-}

	[ -n "${kernel_type}" ] || die "kernel type is empty"
	[ -n "${kernel_version}" ] || die "kernel version is empty"

	info "Installing '${kernel_type}' kernel"

	if [ "$KATA_BUILD_CC" == "yes" ]; then
		build_and_install_kernel_for_cc "$kernel_type"
		return
	fi

	kernel_version=${kernel_version#v}
	local latest_build_url="${jenkins_url}/job/kata-containers-2.0-kernel-${kernel_type}-$(arch)-nightly/${cached_artifacts_path}"
	local kata_config_version=$(cat "${kernel_packaging_dir}/kata_config_version")
	local kata_kernel_version="${kernel_version}-${kata_config_version}"
	local cached_kernel_version=$(curl -sfL "${latest_build_url}/latest") || cached_kernel_version="none"

	info "Kata guest experimental kernel : ${kata_kernel_version}"
	info "cached kernel  : ${cached_kernel_version}"

	source /etc/os-release || source /usr/lib/os-release
	if [[ "${ID}" == "fedora" ]] && [[ "${VERSION_ID}" == "35" ]]; then
		install_prebuilt_kernel ${latest_build_url} ${cached_kernel_version} ||
			die "cannot build a kernel in this system. bug: https://github.com/kata-containers/kata-containers/issues/3145"
		return
	fi

	if [[ "${kata_kernel_version}" != "${cached_kernel_version}" ]] ||
		   ! install_prebuilt_kernel ${latest_build_url} ${cached_kernel_version}; then
	    info "failed to install cached kernel, trying to build from source"
	    build_and_install_kernel "${kernel_type}" "${kernel_version}"
	fi
}

usage() {
	exit_code="$1"
	cat <<EOF
Overview:

	Build and install a kernel for Kata Containers

Usage:

	$script_name [options]

Options:
    -d          : Enable bash debug.
    -h          : Display this help.
    -t <kernel> : kernel type, such as vanilla, experimental, tdx, sev.
EOF
	exit "$exit_code"
}

main() {
	local kernel_type="vanilla"

	while getopts "dht:" opt; do
		case "$opt" in
			d)
				PS4=' Line ${LINENO}: '
				set -x
				;;
			h)
				usage 0
				;;
			t)
				kernel_type="${OPTARG}"
				;;
		esac
	done

	clone_katacontainers_repo

	case "${kernel_type}" in
		experimental)
			install_kernel "${kernel_type}" $(get_version "assets.kernel-experimental.tag")
			;;
		vanilla)
			install_kernel "${kernel_type}" $(get_version "assets.kernel.version")
			;;
		tdx)
			install_kernel "${kernel_type}" $(get_version "assets.kernel.tdx.tag")
			;;
		sev)
			install_kernel "${kernel_type}" $(get_version "assets.kernel.sev.version")
			;;
		dragonball)
			install_kernel "${kernel_type}" $(get_version "assets.dragonball-kernel-experimental.version")
			;;
		*)
			die_unsupported_kernel_type "$kernel_type"
			;;
	esac
}

main $@
