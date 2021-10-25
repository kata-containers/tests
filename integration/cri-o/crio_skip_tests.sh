#!/bin/bash
#
# Copyright (c) 2017-2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

# Currently these are the CRI-O tests that are not working

declare -A skipCRIOTests=(
['test "ctr logging"']='This is not working'
['test "ctr journald logging"']='Not implemented'
['test "ctr logging \[tty=true\]"']='FIXME: See https://github.com/kata-containers/tests/issues/4069'
['test "ctr log max"']='Not implemented'
['test "ctr log max with minimum value"']='Not implemented'
['test "ctr partial line logging"']='This is not working'
['test "ctr execsync"']='FIXME: See https://github.com/cri-o/cri-o/pull/5041'
['test "ctr execsync should not overwrite initial spec args"']='This is not working'
['test "privileged ctr device add"']='FIXME: See https://github.com/cri-o/cri-o/pull/5054'
['test "ctr execsync std{out,err}"']='This is not working'
['test "ctr oom"']='This is not working'
['test "ctr \/etc\/resolv.conf rw\/ro mode"']='This is not working'
['test "ctr create with non-existent command"']='FIXME: See https://github.com/kata-containers/kata-containers/issues/2036'
['test "ctr create with non-existent command \[tty\]"']='FIXME: https://github.com/kata-containers/kata-containers/issues/2036'
['test "ctr update resources"']='This is not working'
['test "ctr resources"']='This is not working'
['test "ctr with non-root user has no effective capabilities"']='This is not working'
['test "ctr with low memory configured should not be created"']='This is not working'
['test "privileged ctr -- check for rw mounts"']='FIXME: See https://github.com/cri-o/cri-o/pull/5054'
['test "annotations passed through"']='This is not working'
['test "ctr with default_env set in configuration"']='This is not working'
['test "ctr with absent mount that should be rejected"']='This is not working'
);

