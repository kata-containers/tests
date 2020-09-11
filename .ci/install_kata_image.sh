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

function handle_error() {
	local exit_code="${?}"
	local line_number="${1:-}"
	echo "Failed at $line_number: ${BASH_COMMAND}"
	exit "${exit_code}"
}
trap 'handle_error $LINENO' ERR

cidir=$(dirname "$0")
cidir=$(realpath "${cidir}")

source /etc/os-release || source /usr/lib/os-release
source "${cidir}/lib.sh"

ARCH="$(${cidir}/kata-arch.sh -d)"

AGENT_INIT=${AGENT_INIT:-no}
TEST_INITRD=${TEST_INITRD:-no}
TEST_CGROUPSV2="${TEST_CGROUPSV2:-false}"
BUILD_WITH_DRACUT="${BUILD_WITH_DRACUT:-no}"
IGNORE_CACHED_ARTIFACTS="${IGNORE_CACHED_ARTIFACTS:-no}"

PREFIX=${PREFIX:-/usr}
IMAGE_DIR=${DESTDIR:-}${PREFIX}/share/kata-containers
IMG_LINK_NAME="kata-containers.img"
INITRD_LINK_NAME="kata-containers-initrd.img"

if [ "${TEST_INITRD}" == "no" ]; then
	OSBUILDER_YAML_INSTALL_NAME="osbuilder-image.yaml"
	LINK_PATH="${IMAGE_DIR}/${IMG_LINK_NAME}"
	IMG_TYPE="image"
else
	OSBUILDER_YAML_INSTALL_NAME="osbuilder-initrd.yaml"
	LINK_PATH="${IMAGE_DIR}/${INITRD_LINK_NAME}"
	IMG_TYPE="initrd"
fi

IMAGE_OS_KEY="assets.${IMG_TYPE}.architecture.$(uname -m).name"
IMAGE_OS_VERSION_KEY="assets.${IMG_TYPE}.architecture.$(uname -m).version"

agent_path="${GOPATH}/src/${agent_repo}"
osbuilder_path="${GOPATH}/src/${osbuilder_repo}"
latest_build_url="${jenkins_url}/job/image-nightly-$(uname -m)/${cached_artifacts_path}"
tag="${1:-""}"

install_ci_cache_image() {
	type=${1}
	check_not_empty "$type" "image type not provided"
	info "Install pre-built ${type}"
	local image_name=$(curl -fsL "${latest_build_url}/latest-${type}")
	sudo mkdir -p "${IMAGE_DIR}"
	pushd "${IMAGE_DIR}" >/dev/null
	local image_path=$(readlink -f "${IMAGE_DIR}/${image_name}")

	sudo -E curl -fsOL "${latest_build_url}/${type}-tarball.sha256sum"
	sudo -E curl -fsL "${latest_build_url}/${image_name}.tar.xz" -o "${image_path}.tar.xz"
	sudo sha256sum -c "${type}-tarball.sha256sum"

	sudo -E curl -fsOL "${latest_build_url}/sha256sum-${type}"
	sudo tar xfv "${image_path}.tar.xz"
	sudo sha256sum -c "sha256sum-${type}"

	sudo -E ln -sf "${image_path}" "${LINK_PATH}"
	sudo -E curl -fsL "${latest_build_url}/${OSBUILDER_YAML_INSTALL_NAME}" -o "${IMAGE_DIR}/${OSBUILDER_YAML_INSTALL_NAME}"

	popd >/dev/null

	if [ ! -L "${LINK_PATH}" ]; then
		echo "Link path not installed: ${LINK_PATH}"
		false
	fi

	if [ ! -f "$(readlink ${LINK_PATH})" ]; then
		echo "Link to ${LINK_PATH} is broken"
		false
	fi
}

check_not_empty() {
	value=${1:-}
	msg=${2:-}
	if [ -z "${value}" ]; then
		echo "${msg}"
		false
	fi
}

build_image_with_dracut() {
	image_output="${1}"
	os_version="${2}"
	agent_commit="${3}"

	check_not_empty "$image_output" "Missing image"
	check_not_empty "$os_version" "Missing OS version"
	check_not_empty "$agent_commit" "Missing agent commit"

	pushd "${osbuilder_path}" >/dev/null

	local image_name=""
	local make_target=""
	if [ "${TEST_INITRD}" == "yes" ]; then
		image_name="kata-containers-initrd.img"
		make_target="initrd"
	else
		make_target="image"
		image_name="kata-containers.img"
	fi

	AGENT_VERSION="${agent_commit}" \
		PATH="$PATH" \
		GOPATH="$GOPATH" \
		OS_VERSION=${os_version} \
		make BUILD_METHOD=dracut \
		AGENT_INIT="${AGENT_INIT}" \
		"$make_target"

	sudo install -o root -g root -m 0640 -D ${image_name} "${IMAGE_DIR}/${image_output}"

	# Unlike the distro method, the dracut-based method doesn't leave
	# behind an unpacked root filesystem tree, so to get access to
	# osbuilder.yaml in order to install it, we need to extract it to
	# a temporary directory from the initrd.
	tmpdir=$(mktemp -d)
	local image_abs_name=${PWD}/${image_name}
	pushd ${tmpdir} >/dev/null
	cat ${image_abs_name} | cpio -idmv var/lib/osbuilder/osbuilder.yaml
	popd >/dev/null

	sudo install -o root -g root -m 0640 -D "${tmpdir}/var/lib/osbuilder/osbuilder.yaml" "${IMAGE_DIR}/${OSBUILDER_YAML_INSTALL_NAME}"

	rm -rf ${tmpdir}

	(cd ${IMAGE_DIR} && sudo ln -sf "${IMAGE_DIR}/${image_output}" "${LINK_PATH}")

	popd >/dev/null
}

build_image() {
	image_output=${1}
	distro=${2}
	os_version=${3}
	agent_commit=${4}

	check_not_empty "$image_output" "Missing image"
	check_not_empty "$distro" "Missing distro"
	check_not_empty "$os_version" "Missing OS version"
	check_not_empty "$agent_commit" "Missing agent commit"

	pushd "${osbuilder_path}" >/dev/null

	# Verify rootfs dir
	if [ "${TEST_CGROUPSV2}" == "true" ] && [ "${TEST_INITRD}" == "yes" ]; then
		distro_name=$(echo "${distro}" | sed 's/./\u&/')
		readonly ROOTFS_DIR="${osbuilder_path}/rootfs-builder/rootfs-${distro_name}"
	else
		readonly ROOTFS_DIR="${PWD}/rootfs"
	fi
	export ROOTFS_DIR
	sudo rm -rf "${ROOTFS_DIR}"

	if [ "${TEST_CGROUPSV2}" == "false" ]; then
		echo "Set runtime as default runtime to build the image"
		bash "${cidir}/../cmd/container-manager/manage_ctr_mgr.sh" docker configure -r runc -f

		sudo -E AGENT_INIT="${AGENT_INIT}" AGENT_VERSION="${agent_commit}" \
			GOPATH="$GOPATH" USE_DOCKER=true OS_VERSION=${os_version} ./rootfs-builder/rootfs.sh "${distro}"
	else
		sudo AGENT_INIT="${AGENT_INIT}" DOCKER_RUNTIME="crun" AGENT_VERSION="${agent_commit}" \
			GOPATH="$GOPATH" USE_PODMAN=true OS_VERSION=${os_version} ./rootfs-builder/rootfs.sh "${distro}"
	fi

	# Build the image
	if [ "${TEST_INITRD}" == "no" ]; then
		if [ "${TEST_CGROUPSV2}" == "true" ]; then
			sudo AGENT_INIT="${AGENT_INIT}" DOCKER_RUNTIME="crun" USE_PODMAN=true ./image-builder/image_builder.sh "$ROOTFS_DIR"
		else
			sudo -E AGENT_INIT="${AGENT_INIT}" USE_DOCKER=true ./image-builder/image_builder.sh "$ROOTFS_DIR"
		fi
		local image_name="kata-containers.img"
	else
		if [ "${TEST_CGROUPSV2}" == "true" ]; then
			sudo AGENT_INIT="${AGENT_INIT}" USE_PODMAN=true DOCKER_RUNTIME="crun" ./initrd-builder/initrd_builder.sh "$ROOTFS_DIR"
		else
			sudo -E AGENT_INIT="${AGENT_INIT}" USE_DOCKER=true ./initrd-builder/initrd_builder.sh "$ROOTFS_DIR"
		fi
		local image_name="kata-containers-initrd.img"
	fi

	sudo install -o root -g root -m 0640 -D ${image_name} "${IMAGE_DIR}/${image_output}"
	sudo install -o root -g root -m 0640 -D "${ROOTFS_DIR}/var/lib/osbuilder/osbuilder.yaml" "${IMAGE_DIR}/${OSBUILDER_YAML_INSTALL_NAME}"
	(cd ${IMAGE_DIR} && sudo ln -sf "${IMAGE_DIR}/${image_output}" "${LINK_PATH}")

	popd >/dev/null
}

#Load specific configure file
if [ -f "${cidir}/${ARCH}/lib_kata_image_${ARCH}.sh" ]; then
	source "${cidir}/${ARCH}/lib_kata_image_${ARCH}.sh"
fi

get_dependencies() {
	info "Pull and install agent on host"
	bash -f "${cidir}/install_agent.sh"
	go get -d "${osbuilder_repo}" || true
	[ -z "${tag}" ] || git -C "${osbuilder_path}" checkout -b "${tag}" "${tag}"
}

main() {
	get_dependencies
	local os_version=""
	local osbuilder_distro=""
	local build_method_suffix=""
	if [ "${BUILD_WITH_DRACUT}" == "yes" ]; then
		os_version="${VERSION_ID}"
		osbuilder_distro="${ID}"
		build_method_suffix=".dracut"
	else
		os_version=$(get_version "${IMAGE_OS_VERSION_KEY}")
		osbuilder_distro=$(get_version "${IMAGE_OS_KEY}")
		# Images were historically built with the "distro" method exclusively so
		# there was no need to indicate a build method in image filename.  To stay
		# compatible, we leave the build method designation for distro-built images
		# empty.
	fi

	if [ "${osbuilder_distro}" == "clearlinux" ] && [ "${os_version}" == "latest" ]; then
		os_version=$(curl -fLs https://download.clearlinux.org/latest)
	fi

	local agent_commit=$(git --work-tree="${agent_path}" --git-dir="${agent_path}/.git" log --format=%h -1 HEAD)
	local osbuilder_commit=$(git --work-tree="${osbuilder_path}" --git-dir="${osbuilder_path}/.git" log --format=%h -1 HEAD)

	image_output="kata-containers-${osbuilder_distro}-${os_version}-osbuilder-${osbuilder_commit}-agent-${agent_commit}"

	if [ "${TEST_INITRD}" == "no" ]; then
		image_output="${image_output}.img${build_method_suffix}"
		type="image"
	else
		image_output="${image_output}.initrd${build_method_suffix}"
		type="initrd"
	fi

	latest_file="latest-${type}${build_method_suffix}"
	info "Image to generate: ${image_output}"

	last_build_image_version=$(curl -fsL "${latest_build_url}/${latest_file}") ||
		last_build_image_version="error-latest-cached-imaget-not-found"

	info "Latest cached image: ${last_build_image_version}"

	if [ "$image_output" == "$last_build_image_version" ] && [ "${IGNORE_CACHED_ARTIFACTS}" == "no" ]; then
		info "Cached image is same to be generated"
		if ! install_ci_cache_image "${type}"; then
			info "failed to install cached image, trying to build from source"
			build_image "${image_output}" "${osbuilder_distro}" "${os_version}" "${agent_commit}"
		fi
	else
		if [ "${BUILD_WITH_DRACUT}" == "yes" ]; then
			build_image_with_dracut "${image_output}" "${os_version}" "${agent_commit}"
		else
			build_image "${image_output}" "${osbuilder_distro}" "${os_version}" "${agent_commit}"
		fi
	fi

	if [ ! -L "${LINK_PATH}" ]; then
		die "Link path not installed: ${LINK_PATH}"
	fi

	if [ ! -f "$(readlink ${LINK_PATH})" ]; then
		die "Link to ${LINK_PATH} is broken"
	fi
}

main $@
