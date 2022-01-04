# Copyright (c) 2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

# Usage: FROM [image name]
FROM ubuntu:16.04

# Version of the Dockerfile
LABEL DOCKERFILE_VERSION="1.0"

# Install iperf
RUN apt-get update && \
    apt-get remove -y unattended-upgrades && \
    apt-get install -y --no-install-recommends iperf && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists


CMD ["/bin/bash"]
