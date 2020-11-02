#! /bin/bash
#
# Copyright (c) 2021 Ant Group
#
# SPDX-License-Identifier: Apache-2.0
#

TIMEOUT=${TIMEOUT:-60}

# A simple exepct script to help validating readonly volumes
# Run with ro-volume-exp.sh <sandbox-id> <volume-suffix>
expect -c "
  set timeout $TIMEOUT
  spawn kata-runtime exec $1
  send \"cd /run/kata-containers/shared/containers/*$2/\n\"
  send \"echo 1 > foo\n\"
  send \"exit\n\"
  interact
"
