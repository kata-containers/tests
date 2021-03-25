#!/bin/bash
#
# Copyright (c) 2019 Ant Financial
#
# SPDX-License-Identifier: Apache-2.0

set -e

[ -n "${KATA_DEV_MODE:-}" ] && exit 0

cidir=$(dirname "$0")
source "${cidir}/lib.sh"

rustarch=$(${cidir}/kata-arch.sh --rust)
# release="nightly"
# recent functional version
version="${1:-""}"
if [ -z "${version}" ]; then
	version=$(get_version "languages.rust.meta.newest-version")
fi

if ! command -v rustup > /dev/null; then
	curl https://sh.rustup.rs -sSf | sh -s -- -y
fi

export PATH="${PATH}:${HOME}/.cargo/bin"

echo "Install rust"
rustup toolchain install ${version}
rustup default ${version}
if [ "${rustarch}" == "powerpc64le" ] || [ "${rustarch}" == "s390x" ] ; then
	rustup target add ${rustarch}-unknown-linux-gnu
else
	rustup target add ${rustarch}-unknown-linux-musl
	sudo ln -sf /usr/bin/g++ /bin/musl-g++
fi
rustup component add rustfmt
