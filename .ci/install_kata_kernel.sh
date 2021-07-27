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

cidir=$(dirname "$0")
source "${cidir}/lib.sh"

latest_build_url="${jenkins_url}/job/kata-containers-2.0-kernel-vanilla-$(arch)-nightly/${cached_artifacts_path}"
PREFIX="${PREFIX:-/usr}"
kernel_dir="${DESTDIR:-}${PREFIX}/share/kata-containers"

kernel_packaging_dir="${kata_repo_dir}/tools/packaging/kernel"
readonly tmp_dir="$(mktemp -d -t install-kata-XXXXXXXXXXX)"

exit_handler() {
	rm -rf "${tmp_dir}"
}

trap exit_handler EXIT

build_and_install_kernel() {
	# Always build and install the kernel version found locally
	info "Install kernel from sources"
	pushd "${tmp_dir}" >> /dev/null
	"${kernel_packaging_dir}/build-kernel.sh" -v "${kernel_version}" "setup"
	"${kernel_packaging_dir}/build-kernel.sh" -v "${kernel_version}" "build"
	sudo -E PATH="$PATH" "${kernel_packaging_dir}/build-kernel.sh" -v "${kernel_version}" "install"
	popd >> /dev/null
}

# $1 kernel_binary: binary to install could be vmlinux or vmlinuz
install_cached_kernel(){
	local kernel_binary=${1:-}
	[ -z "${kernel_binary}" ] && die "empty binary format"
	info "Installing ${kernel_binary}"
	sudo mkdir -p "${kernel_dir}"
	local kernel_binary_name="${kernel_binary}-${cached_kernel_version}"
	local kernel_binary_path="${kernel_dir}/${kernel_binary_name}"
	curl -fL --progress-bar "${latest_build_url}/${kernel_binary_name}" -o "${tmp_dir}/${kernel_binary_name}" || return 1
	sudo mv ${tmp_dir}/${kernel_binary_name} ${kernel_binary_path}
	kernel_symlink="${kernel_dir}/${kernel_binary}.container"
	info "Installing ${kernel_binary_path} and symlink ${kernel_symlink}"
	sudo -E ln -sf "${kernel_binary_path}" "${kernel_symlink}"
}

install_prebuilt_kernel() {
	info "Install pre-built kernel version"

	for k in "vmlinux" "vmlinuz"; do
		install_cached_kernel "${k}" || return 1
	done

	pushd "${kernel_dir}" >/dev/null
	info "Verify download checksum"
	curl -fsL "${latest_build_url}/sha256sum-kernel" -o ${tmp_dir}/sha256sum-kernel || return 1
	sudo mv ${tmp_dir}/sha256sum-kernel .
	sudo sha256sum -c "sha256sum-kernel" || return 1
	popd >/dev/null
}

main() {
	clone_kata_repo
	kernel_version=$(get_version "assets.kernel.version")
	kernel_version=${kernel_version#v}
	kata_config_version=$(cat "${kernel_packaging_dir}/kata_config_version")
	current_kernel_version="${kernel_version}-${kata_config_version}"
	cached_kernel_version=$(curl -sfL "${latest_build_url}/latest") || cached_kernel_version="none"
	info "current kernel : ${current_kernel_version}"
	info "cached kernel  : ${cached_kernel_version}"
	if [ "$cached_kernel_version" == "$current_kernel_version" ] && [ "$(arch)" == "x86_64" ]; then
		# If installing kernel fails,
		# then build and install it from sources.
		if ! install_prebuilt_kernel; then
			info "failed to install cached kernel, trying to build from source"
			build_and_install_kernel
		fi
	else
		build_and_install_kernel
	fi
}

main
