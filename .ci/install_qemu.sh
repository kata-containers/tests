#!/bin/bash
#
# Copyright (c) 2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -e

cidir=$(dirname "$0")
source "${cidir}/lib.sh"
source /etc/os-release || source /usr/lib/os-release

CURRENT_QEMU_BRANCH=$(get_version "assets.hypervisor.qemu.version")
CURRENT_QEMU_COMMIT=$(get_version "assets.hypervisor.qemu.commit")
PACKAGED_QEMU="qemu-vanilla"
QEMU_ARCH=$(${cidir}/kata-arch.sh -d)

get_packaged_qemu_commit() {
	if [ "$ID" == "ubuntu" ] || [ "$ID" == "debian" ]; then
		qemu_commit=$(sudo apt-cache madison $PACKAGED_QEMU \
			| awk '{print $3}' | cut -d'-' -f1 | cut -d'.' -f4)
	elif [ "$ID" == "fedora" ]; then
		qemu_commit=$(sudo dnf --showduplicate list ${PACKAGED_QEMU}.${QEMU_ARCH} \
			| awk '/'$PACKAGED_QEMU'/ {print $2}' | cut -d'-' -f1 | cut -d'.' -f4)
	elif [ "$ID" == "centos" ]; then
		qemu_commit=$(sudo yum --showduplicate list $PACKAGED_QEMU \
			| awk '/'$PACKAGED_QEMU'/ {print $2}' | cut -d'-' -f1 | cut -d'.' -f4)
	elif [[ "$ID" =~ ^opensuse.*$ ]] || [ "$ID" == "sles" ]; then
		qemu_commit=$(sudo zypper info $PACKAGED_QEMU \
			| grep "Version" | sed -E "s/.+\+git\.([0-9a-f]+).+/\1/")
	fi

	echo "${qemu_commit}"
}

install_packaged_qemu() {
	rc=0
	# Timeout to download packages from OBS
	limit=180
	if [ "$ID"  == "ubuntu" ] || [ "$ID" == "debian" ]; then
		chronic sudo apt remove -y "$PACKAGED_QEMU" || true
		chronic sudo apt install -y "$PACKAGED_QEMU" || rc=1
	elif [ "$ID"  == "fedora" ]; then
		chronic sudo dnf remove -y "$PACKAGED_QEMU" || true
		chronic sudo dnf install -y "$PACKAGED_QEMU" || rc=1
	elif [ "$ID"  == "centos" ]; then
		chronic sudo yum remove -y "$PACKAGED_QEMU" || true
		chronic sudo yum install -y "$PACKAGED_QEMU" || rc=1
	elif [[ "$ID" =~ ^opensuse.*$ ]] || [ "$ID" == "sles" ]; then
		chronic sudo zypper -n remove "$PACKAGED_QEMU" || true
		chronic sudo zypper -n install "$PACKAGED_QEMU" || rc=1
	else
		die "Unrecognized distro"
	fi

	return "$rc"
}

build_and_install_qemu() {
	QEMU_REPO_URL=$(get_version "assets.hypervisor.qemu.url")
	# Remove 'https://' from the repo url to be able to clone the repo using 'go get'
	QEMU_REPO=${QEMU_REPO_URL/https:\/\//}
	PACKAGING_REPO="github.com/kata-containers/packaging"
	QEMU_CONFIG_SCRIPT="${GOPATH}/src/${PACKAGING_REPO}/scripts/configure-hypervisor.sh"

	mkdir -p "${GOPATH}/src"
	git clone --branch "$CURRENT_QEMU_BRANCH" --single-branch "${QEMU_REPO_URL}" "${GOPATH}/src/${QEMU_REPO}"
	go get -d "$PACKAGING_REPO" || true

	pushd "${GOPATH}/src/${QEMU_REPO}"
	git fetch
	git checkout "$CURRENT_QEMU_COMMIT"
	[ -n "$(ls -A capstone)" ] || git clone https://github.com/qemu/capstone.git capstone
	[ -n "$(ls -A ui/keycodemapdb)" ] || git clone  https://github.com/qemu/keycodemapdb.git ui/keycodemapdb

	echo "Build Qemu"
	"${QEMU_CONFIG_SCRIPT}" "qemu" | xargs ./configure
	make -j $(nproc)

	echo "Install Qemu"
	sudo -E make install

	popd
}

#Load specific configure file
if [ -f "${cidir}/${QEMU_ARCH}/lib_install_qemu_${QEMU_ARCH}.sh" ]; then
	source "${cidir}/${QEMU_ARCH}/lib_install_qemu_${QEMU_ARCH}.sh"
fi

main() {
	case "$QEMU_ARCH" in
		"x86_64")
			packaged_qemu_commit=$(get_packaged_qemu_commit)
			short_current_qemu_commit=${CURRENT_QEMU_COMMIT:0:10}
			if [ "$packaged_qemu_commit" == "$short_current_qemu_commit" ]; then
				# If installing packaged qemu from OBS fails,
				# then build and install it from sources.
				install_packaged_qemu || build_and_install_qemu
			else
				build_and_install_qemu
			fi
			;;
		"aarch64"|"ppc64le"|"s390x")
			packaged_qemu_version=$(get_packaged_qemu_version)
			short_current_qemu_version=${CURRENT_QEMU_VERSION#*-}
			if [ "$packaged_qemu_version" == "$short_current_qemu_version" ] && [ -z "${CURRENT_QEMU_COMMIT}" ] || [ "${QEMU_ARCH}" == "s390x" ]; then
				install_packaged_qemu || build_and_install_qemu
			else
				build_and_install_qemu
			fi
			;;
		*)
			die "Architecture $QEMU_ARCH not supported"
			;;
	esac
}

main
