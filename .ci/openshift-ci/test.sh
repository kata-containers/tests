#!/bin/bash
#
# Copyright (c) 2020 Red Hat, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#

set -x

script_dir=$(dirname $0)
source ${script_dir}/../lib.sh

# Make oc and kubectl visible
export PATH=/tmp/shared:$PATH

oc version || die "Test cluster is unreachable"

info "Install and configure kata into the test cluster"
${script_dir}/cluster/install_kata.sh || die "Failed to install kata-containers"
