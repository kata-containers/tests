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
version="${1:-""}"
if [ -z "${version}" ]; then
	version=$(get_version "languages.rust.version")
fi

echo "Install rust ${version}"

if ! command -v rustup > /dev/null; then
	curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain ${version}
fi

export PATH="${PATH}:${HOME}/.cargo/bin"

## Still try to install the target version of toolchain,
## in case that the rustup has been installed but
## with a different version toolchain.
## Even though the target version toolchain has been installed,
## this command will not take too long to run.
rustup toolchain install ${version}
rustup default ${version}
if [ "${rustarch}" == "powerpc64le" ] || [ "${rustarch}" == "s390x" ] ; then
	rustup target add ${rustarch}-unknown-linux-gnu
else
	rustup target add ${rustarch}-unknown-linux-musl
	$([ "$(whoami)" != "root" ] && echo sudo) ln -sf /usr/bin/g++ /bin/musl-g++
fi
rustup component add rustfmt
