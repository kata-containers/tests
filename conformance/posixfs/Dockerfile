# Copyright (c) 2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

# Usage: FROM [image name]
FROM debian:bullseye

# Version of the Dockerfile
LABEL DOCKERFILE_VERSION="1.0"

RUN apt-get update && \
    apt-get -y --no-install-recommends install autoconf git bc libacl1-dev libacl1 acl gcc make perl g++ perl-modules && \
    apt-get clean && rm -rf /var/lib/apt/lists && \
    git clone https://github.com/pjd/pjdfstest.git /pjdfstest
WORKDIR /pjdfstest
RUN autoreconf -ifs && \
    ./configure && \
    make

CMD ["/bin/bash"]
