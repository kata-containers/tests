#!/bin/bash
#
# Copyright (c) 2017-2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

# Currently these are the CRI-O tests that are not working

declare -a skipCRIOTests=(
'test "ctr lifecycle"'
'test "ctr logging"'
'test "ctr journald logging"'
'test "ctr logging \[tty=true\]"' # FIXME: See https://github.com/kata-containers/tests/issues/4069
'test "ctr log max"'
'test "ctr log max with minimum value"'
'test "ctr partial line logging"'
'test "ctr execsync"'
'test "ctr execsync should not overwrite initial spec args"'
'test "privileged ctr device add"'
'test "ctr execsync std{out,err}"'
'test "ctr oom"'
'test "ctr \/etc\/resolv.conf rw\/ro mode"'
'test "ctr create with non-existent command"'
'test "ctr create with non-existent command \[tty\]"'
'test "ctr update resources"'
'test "ctr resources"'
'test "ctr with non-root user has no effective capabilities"'
'test "ctr with low memory configured should not be created"'
'test "privileged ctr -- check for rw mounts"'
'test "annotations passed through"'
'test "ctr with default_env set in configuration"'
'test "ctr with absent mount that should be rejected"'
);

