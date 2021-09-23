#!/bin/bash
#
# Copyright (c) 2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

cidir=$(dirname "$0")
source "${cidir}/lib.sh"
source "${cidir}/../lib/common.bash"
source /etc/os-release || source /usr/lib/os-release

PREFIX=${PREFIX:-/usr}
KATA_DEV_MODE="${KATA_DEV_MODE:-}"

CURRENT_QEMU_VERSION=$(get_version "assets.hypervisor.qemu.version")
QEMU_REPO_URL=$(get_version "assets.hypervisor.qemu.url")
# Remove 'https://' from the repo url to be able to git clone the repo
QEMU_REPO=${QEMU_REPO_URL/https:\/\//}
QEMU_ARCH=$(${cidir}/kata-arch.sh -d)
PACKAGING_DIR="${kata_repo_dir}/tools/packaging"
ARCH=$("${cidir}"/kata-arch.sh -d)
QEMU_TAR="kata-static-qemu.tar.gz"
qemu_latest_build_url="${jenkins_url}/job/kata-containers-2.0-qemu-$(uname -m)/${cached_artifacts_path}"

# option "--shallow-submodules" was introduced in git v2.9.0
GIT_SHADOW_VERSION="2.9.0"

# We need to move the tar file to a specific location so we
# can know where it is and then we can perform the build cache
# operations
update_cache() {
	sudo mkdir -p "${KATA_TESTS_CACHEDIR}"
	sudo mv ${QEMU_TAR} ${KATA_TESTS_CACHEDIR}
}

build_static_qemu() {
	info "building static QEMU"
	# only x86_64 is supported for building static QEMU
	[ "$ARCH" != "x86_64" ] && return 1

	(
	cd "${PACKAGING_DIR}/static-build/qemu"
	prefix="${KATA_QEMU_DESTDIR}" make

	update_cache
	)
}

uncompress_static_qemu() {
	local qemu_tar_location="$1"
	[ -n "$qemu_tar_location" ] || die "provide the location of the QEMU compressed file"
	sudo tar -xf "${qemu_tar_location}" -C /
	# verify installed binaries existance
	ls /usr/libexec/kata-qemu/virtiofsd || return 1
	ls /usr/bin/qemu-system-x86_64 || return 1
}

build_and_install_static_qemu() {
	build_static_qemu
	uncompress_static_qemu "${KATA_TESTS_CACHEDIR}/${QEMU_TAR}"
}

install_cached_qemu() {
	info "Installing cached QEMU"
	curl -fL --progress-bar "${qemu_latest_build_url}/${QEMU_TAR}" -o "${QEMU_TAR}" || return 1
	curl -fsOL "${qemu_latest_build_url}/sha256sum-${QEMU_TAR}" || return 1

	sha256sum -c "sha256sum-${QEMU_TAR}" || return 1
	uncompress_static_qemu "${QEMU_TAR}"
	update_cache
}

clone_qemu_repo() {
	# check if git is capable of shadow cloning
        git_shadow_clone=$(check_git_version "${GIT_SHADOW_VERSION}")

	if [ "$git_shadow_clone" == "true" ]; then
		git clone --branch "${CURRENT_QEMU_VERSION}" --single-branch --depth 1 --shallow-submodules "${QEMU_REPO_URL}" "${GOPATH}/src/${QEMU_REPO}"
	else
		git clone --branch "${CURRENT_QEMU_VERSION}" --single-branch --depth 1 "${QEMU_REPO_URL}" "${GOPATH}/src/${QEMU_REPO}"
	fi
}

build_and_install_qemu() {
	if [ -n "$(command -v qemu-system-${QEMU_ARCH})" ] && [ -n "$KATA_DEV_MODE" ]; then
		die "QEMU will not be installed"
	fi

	QEMU_CONFIG_SCRIPT="${PACKAGING_DIR}/scripts/configure-hypervisor.sh"

	mkdir -p "${GOPATH}/src"

	clone_kata_repo
	clone_qemu_repo

	pushd "${GOPATH}/src/${QEMU_REPO}"
	git fetch
	[ -n "$(ls -A capstone)" ] || git clone https://github.com/qemu/capstone.git capstone
	[ -n "$(ls -A ui/keycodemapdb)" ] || git clone  https://github.com/qemu/keycodemapdb.git ui/keycodemapdb

	# Apply required patches
	${PACKAGING_DIR}/scripts/patch_qemu.sh ${CURRENT_QEMU_VERSION} ${PACKAGING_DIR}/qemu/patches

	echo "Build QEMU"
	# Not all distros have the libpmem package
	"${QEMU_CONFIG_SCRIPT}" "qemu" |
		if [ "${NAME}" == "Ubuntu" ] && [ "$(echo "${VERSION_ID} < 18.04" | bc -q)" == "1" ]; then
			sed -e 's/--enable-libpmem/--disable-libpmem/g'
		else
			cat
		fi | xargs ./configure --prefix=${PREFIX}
	make -j $(nproc)

	echo "Install QEMU"
	sudo -E make install
	# qemu by default installs virtiofsd under libexec
	sudo mkdir -p /usr/libexec/kata-qemu/
	sudo ln -sf ${PREFIX}/libexec/qemu/virtiofsd /usr/libexec/kata-qemu/virtiofsd
	ls -l /usr/libexec/kata-qemu/virtiofsd || return 1
	popd
}

#Load specific configure file
if [ -f "${cidir}/${QEMU_ARCH}/lib_install_qemu_${QEMU_ARCH}.sh" ]; then
	source "${cidir}/${QEMU_ARCH}/lib_install_qemu_${QEMU_ARCH}.sh"
fi

main() {
	case "$QEMU_ARCH" in
		"x86_64")
			# latest is "version sha256sum"
			latest=$(curl -sfL "${qemu_latest_build_url}/latest") || latest="none"
			cached_qemu_version=$(echo $latest | awk '{print $1}')
			info "current QEMU version: $CURRENT_QEMU_VERSION"
			info "cached QEMU version: $cached_qemu_version"

			if [ -n "${FORCE_BUILD_QEMU:-}" ]; then
				build_and_install_qemu
			elif [ "$CURRENT_QEMU_VERSION" == "$cached_qemu_version" ]; then
				# Let's check if the current sha256sum matches
				# with the cached, otherwise build QEMU locally
				current_sha256sum="$(calc_qemu_files_sha256sum)"
				[ -n "$current_sha256sum" ] || \
					die "Failed to calculate SHA-256 for QEMU"
				cached_sha256sum="$(echo $latest | awk '{print $2}')"
				if [ "$current_sha256sum" == "$cached_sha256sum" ]; then
					# If installing cached QEMU fails,
					# then build and install it from sources.
					install_cached_qemu || build_and_install_static_qemu
				else
					warn "Mismatch of cached ($cached_sha256sum) and expected ($current_sha256sum) versions"
					build_and_install_static_qemu
				fi
			else
				build_and_install_static_qemu
			fi
			;;
		"aarch64"|"ppc64le"|"s390x")
			build_and_install_qemu
			;;
		*)
			die "Architecture $QEMU_ARCH not supported"
			;;
	esac
}

main
