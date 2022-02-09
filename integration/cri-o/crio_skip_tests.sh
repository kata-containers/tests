#!/bin/bash
#
# Copyright (c) 2017-2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

# TODO: the list of files is hardcoded for now, as we don't have listed all tests
# that need to be skipped, but ultimately we will want to use *.bats
declare -a bats_files_list=("ctr.bats")

# Currently these are the CRI-O tests that are not working

declare -A skipCRIOTests=(
['test "ctr logging"']='This is not working'
['test "ctr journald logging"']='Not implemented'
['test "ctr logging \[tty=true\]"']='FIXME: See https://github.com/kata-containers/tests/issues/4069'
['test "ctr log max"']='Not implemented'
['test "ctr log max with minimum value"']='Not implemented'
['test "ctr partial line logging"']='This is not working'
['test "ctr execsync should not overwrite initial spec args"']='This is not working'
['test "ctr execsync std{out,err}"']='This is not working'
['test "ctr oom"']='This is not working'
['test "ctr \/etc\/resolv.conf rw\/ro mode"']='This is not working'
['test "ctr create with non-existent command"']='FIXME: See https://github.com/kata-containers/kata-containers/issues/2036'
['test "ctr create with non-existent command \[tty\]"']='FIXME: https://github.com/kata-containers/kata-containers/issues/2036'
['test "ctr update resources"']='This is not working'
['test "ctr resources"']='This is not working'
['test "ctr with non-root user has no effective capabilities"']='This is not working'
['test "ctr with low memory configured should not be created"']='This is not working'
['test "annotations passed through"']='This is not working'
['test "ctr with default_env set in configuration"']='This is not working'
['test "ctr with absent mount that should be rejected"']='This is not working'
);

# The following lists tests that should be skipped in specific cri-o versions.
# When adding a test here, you need to provide the version of cri-o where the
# bug was fixed. The script will skip this test in all previous versions.
declare -A fixedInCrioVersion=(
['test "privileged ctr device add"']="1.22"
['test "privileged ctr -- check for rw mounts"']="1.22"
['test "ctr execsync"']="1.22"
);

