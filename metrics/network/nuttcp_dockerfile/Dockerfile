# Copyright (c) 2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

# Usage: FROM [image name]
# hadolint ignore=DL3007
FROM ubuntu:latest

# Version of the Dockerfile
LABEL DOCKERFILE_VERSION="1.0"

# Version of nuttcp
ARG NUTTCP_VERSION="7.3.2"

# Install iperf
RUN apt-get update && \
    apt-get remove -y unattended-upgrades && \
    apt-get install --no-install-recommends -y \
    build-essential \
    curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists


# Install nuttcp (Network performance measurement tool)
RUN cd "$HOME" && \
    curl -OkL "http://nuttcp.net/nuttcp/beta/nuttcp-${NUTTCP_VERSION}.c" && \
    gcc nuttcp-${NUTTCP_VERSION}.c -o nuttcp

CMD ["/bin/bash"]
