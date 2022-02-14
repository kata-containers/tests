#!/bin/bash
#
# Copyright (c) 2017-2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

# TODO: the list of files is hardcoded for now, as we don't have listed all tests
# that need to be skipped, but ultimately we will want to use *.bats
# The file name is provided without its ".bats" extension for easier processing.
declare -a bats_files_list=("ctr")

# We keep two lists for each bats file.
# - [name]_skipCRIOTests for tests that we need to skip because of failures
# - [name]_fixedInCrioVersion for tests that we need to skip when running
#   with a version of cri-o that doesn't have the fix
#
# In both case, [name] is the basename of the bats file containing the tests.


declare -A ctr_skipCRIOTests=(
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
declare -A ctr_fixedInCrioVersion=(
['test "privileged ctr device add"']="1.22"
['test "privileged ctr -- check for rw mounts"']="1.22"
['test "ctr execsync"']="1.22"
);

