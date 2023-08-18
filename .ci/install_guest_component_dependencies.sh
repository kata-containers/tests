#!/bin/bash
#
# Copyright Confidential Containers Contributors
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail

# Detect if the OS is Ubuntu or fedora
source "/etc/os-release" || source "/usr/lib/os-release"

# On Ubuntu or debian, install the dependencies
if [ "$ID" == "ubuntu" ] || [ "$ID" == "debian" ]; then
    export DEBIAN_FRONTEND=noninteractive
    sudo apt update
    sudo apt install -y \
        libdevmapper-dev \
        clang

    exit 0
fi

# On Fedora, install the dependencies
if [ "$ID" == "fedora" ]; then
    sudo dnf install -y \
        device-mapper-devel \
        clang

    exit 0
fi

# On CentOS 8 Stream
if [ "$ID" == "centos" ] && [ "$VERSION_ID" == "8" ]; then
    # Enable powertools repo to be able to install the developer library for device-mapper
    sudo yum install -y \
        dnf-plugins-core
    sudo yum config-manager --set-enabled powertools

    sudo yum install -y \
        device-mapper-devel \
        clang
    exit 0
fi

echo "Unsupported OS: $PRETTY_NAME"
exit 1
