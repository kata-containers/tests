# Copyright (c) 2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

# Usage: FROM [image name]
FROM fedora:34

# Version of the Dockerfile
LABEL DOCKERFILE_VERSION="1.0"

# Install iperf3
RUN dnf -y update && \
    dnf -y install iperf3 && \
    dnf clean all

CMD ["/bin/bash"]
