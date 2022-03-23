#!/bin/bash
#
# Copyright (c) 2017-2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

# TODO: the list of files is hardcoded for now, as we don't have listed all tests
# that need to be skipped, but ultimately we will want to use *.bats
# The file name is provided without its ".bats" extension for easier processing.
declare -a bats_files_list=(
    "ctr"
    "cgroups"
    "command"
    "config"
    "config_migrate"
    "crio-wipe"
#    "ctr_seccomp" see https://github.com/kata-containers/tests/issues/4587
    "default_mounts"
    "devices"
    "drop_infra"
    "hooks"
    "image"
    "image_remove"
    "image_volume"
    "infra_ctr_cpuset"
    "inspect"
    "inspecti"
    "metrics"
    "namespaces"
    "network"
    "network_ping"
    "pod"
    "profile"
    "reload_config"
    "reload_system"
    "restore"
    "runtimeversion"
    "sanity_checks"
    "selinux"
    "shm"
    "shm_size"
    "stats"
    "status"
    )
# We keep two lists for each bats file.
# - [name]_skipCRIOTests for tests that we need to skip because of failures
# - [name]_fixedInCrioVersion for tests that we need to skip when running
#   with a version of cri-o that doesn't have the fix
#
# In both case, [name] is the basename of the bats file containing the tests.

#This issue($url) - tracking crio integration test cases are skipped.
url=https://github.com/kata-containers/tests/issues/4459

declare -A ctr_skipCRIOTests=(
['test "ctr logging"']="This is not working: see `eval echo $url`"
['test "ctr journald logging"']='Not implemented'
['test "ctr logging \[tty=true\]"']='FIXME: See https://github.com/kata-containers/tests/issues/4069'
['test "ctr log max"']='Not implemented'
['test "ctr log max with minimum value"']='Not implemented'
['test "ctr partial line logging"']="This is not working: see `eval echo $url`"
['test "ctr execsync should not overwrite initial spec args"']="This is not working: see `eval echo $url`"
['test "ctr execsync std{out,err}"']="This is not working: see `eval echo $url`"
['test "ctr oom"']="This is not working: see `eval echo $url`"
['test "ctr \/etc\/resolv.conf rw\/ro mode"']="This is not working: see `eval echo $url`"
['test "ctr create with non-existent command"']='FIXME: See https://github.com/kata-containers/kata-containers/issues/2036'
['test "ctr create with non-existent command \[tty\]"']='FIXME: https://github.com/kata-containers/kata-containers/issues/2036'
['test "ctr update resources"']="This is not working: see `eval echo $url`"
['test "ctr resources"']="This is not working: see `eval echo $url`"
['test "ctr with non-root user has no effective capabilities"']="This is not working: see `eval echo $url`"
['test "ctr with low memory configured should not be created"']="This is not working: see `eval echo $url`"
['test "annotations passed through"']="This is not working: see `eval echo $url`"
['test "ctr with default_env set in configuration"']="This is not working: see `eval echo $url`"
['test "ctr with absent mount that should be rejected"']="This is not working: see `eval echo $url`"
)
declare -A cgroups_skipCRIOTests=(
['test "ctr with swap should fail when swap is lower"']="cgroups.bats case is not working: see `eval echo $url`"
['test "ctr with swap should be configured"']="cgroups.bats case is not working: see `eval echo $url`"
['test "pids limit"']="cgroups.bats case is not working: see `eval echo $url`"
['test "conmon custom cgroup"']='conmon is not involved with kata runtime'
['test "cgroupv2 unified support"']="cgroups.bats case is not working: see `eval echo $url`"
)
declare -A command_skipCRIOTests=(
['test "log max boundary testing"']="command.bats case is not working: see `eval echo $url`"
['test "crio commands"']="command.bats case is not working: see `eval echo $url`"
)
declare -A config_skipCRIOTests=(
['test "replace default runtime should succeed"']="config.bats case is not working: see `eval echo $url`"
['test "retain default runtime should succeed"']="config.bats case is not working: see `eval echo $url`"
)
declare -A config_migrate_skipCRIOTests=(
['test "config migrate should succeed with default config"']="config_migrate.bats case is not working: see `eval echo $url`"
['test "config migrate should succeed with 1.17 config"']="config_migrate.bats case is not working: see `eval echo $url`"
)
declare -A criowipe_skipCRIOTests=(
['test "clear neither when remove persist"']="crio-wipe.bats case is not working: see `eval echo $url`"
[$'test "don\'t clear containers on a forced restart of crio"']="crio-wipe.bats case is not working: see `eval echo $url`"
[$'test "don\'t clear containers if clean shutdown supported file not present"']="crio-wipe.bats case is not working: see `eval echo $url`"
[$'test "internal_wipe don\'t clear containers on a forced restart of crio"']="crio-wipe.bats case is not working: see `eval echo $url`"
['test "internal_wipe eventually cleans network on forced restart of crio if network is slow to come up"']="crio-wipe.bats case is not working: see `eval echo $url`"
)
declare -A ctr_seccomp_skipCRIOTests=(
['test "ctr seccomp profiles runtime\/default"']="ctr_seccomp.bats case is not working: see `eval echo $url`"
['test "ctr seccomp profiles localhost\/profile_name"']="ctr_seccomp.bats case is not working: see `eval echo $url`"
['test "ctr seccomp profiles docker\/default"']="ctr_seccomp.bats case is not working: see `eval echo $url`"
['test "ctr seccomp overrides unconfined profile with runtime\/default when overridden"']="ctr_seccomp.bats case is not working: see `eval echo $url`"
)
declare -A devices_skipCRIOTests=(
['test "additional devices permissions"']="devices.bats case is not working: see `eval echo $url`"
['test "annotation devices support"']="devices.bats case is not working: see `eval echo $url`"
['test "annotation should override configured additional_devices"']="devices.bats case is not working: see `eval echo $url`"
['test "annotation should not be processed if not allowed in allowed_devices"']="devices.bats case is not working: see `eval echo $url`"
['test "annotation should configure multiple devices"']="devices.bats case is not working: see `eval echo $url`"
['test "annotation should fail if one device is invalid"']="devices.bats case is not working: see `eval echo $url`"
)
declare -A drop_infra_skipCRIOTests=(
['test "test infra ctr dropped"']="drop_infra.bats case is not working: see `eval echo $url`"
['test "test infra ctr not dropped"']="drop_infra.bats case is not working: see `eval echo $url`"
)
declare -A image_skipCRIOTests=(
['test "image pull and list by manifest list digest"']="image.bats case is not working: see `eval echo $url`"
['test "image pull and list by manifest list tag"']="image.bats case is not working: see `eval echo $url`"
['test "image pull and list by manifest list and individual digest"']="image.bats case is not working: see `eval echo $url`"
['test "image pull and list by individual and manifest list digest"']="image.bats case is not working: see `eval echo $url`"
['test "image pull with signature"']='skip registry has some issues'
['test "container status when created by image list canonical reference"']="drop_infra.bats case is not working: see `eval echo $url`"
)
declare -A infra_ctr_cpuset_skipCRIOTests=(
['test "test infra ctr cpuset"']="infra_ctr_cpuset.bats case is not working: see `eval echo $url`"
)
declare -A inspect_skipCRIOTests=(
['test "info inspect"']="inspect.bats case is not working: see `eval echo $url`"
['test "ctr inspect"']="inspect.bats case is not working: see `eval echo $url`"
['test "pod inspect when dropping infra"']="inspect.bats case is not working: see `eval echo $url`"
['test "ctr inspect not found"']="inspect.bats case is not working: see `eval echo $url`"
)
declare -A metrics_skipCRIOTests=(
['test "metrics with default port"']="metrics.bats case is not working: see `eval echo $url`"
['test "metrics with random port"']="metrics.bats case is not working: see `eval echo $url`"
['test "metrics with operations quantile"']="metrics.bats case is not working: see `eval echo $url`"
['test "secure metrics with random port"']="metrics.bats case is not working: see `eval echo $url`"
['test "secure metrics with random port and missing cert\/key"']="metrics.bats case is not working: see `eval echo $url`"
['test "metrics container oom"']="metrics.bats case is not working: see `eval echo $url`"
)
declare -A namespaces_skipCRIOTests=(
['test "pid namespace mode target test"']="namespaces.bats case is not working: see `eval echo $url`"
)
declare -A network_skipCRIOTests=(
['test "ensure correct hostname for hostnetwork:true"']="network.bats case is not working: see `eval echo $url`"
['test "Connect to pod hostport from the host"']="network.bats case is not working: see `eval echo $url`"
['test "Clean up network if pod sandbox fails"']="network.bats case is not working: see `eval echo $url`"
['test "Clean up network if pod sandbox gets killed"']="network.bats case is not working: see `eval echo $url`"
)
declare -A network_ping_skipCRIOTests=(
['test "Ping pod from the host \/ another pod"']="network_ping.bats case is not working: see `eval echo $url`"
)
declare -A pod_skipCRIOTests=(
['test "pass pod sysctls to runtime"']="pod.bats case is not working: see `eval echo $url`"
['test "restart crio and still get pod status"']="pod.bats case is not working: see `eval echo $url`"
['test "systemd cgroup_parent correctly set"']="pod.bats case is not working: see `eval echo $url`"
['test "kubernetes pod terminationGracePeriod passthru"']="pod.bats case is not working: see `eval echo $url`"
['test "skip pod sysctls to runtime if host"']="pod.bats case is not working: see `eval echo $url`"
)
declare -A restore_skipCRIOTests=(
['test "crio restore with bad state and pod stopped"']="restore.bats case is not working: see `eval echo $url`"
['test "crio restore with bad state and ctr stopped"']="restore.bats case is not working: see `eval echo $url`"
['test "crio restore with bad state and ctr removed"']="restore.bats case is not working: see `eval echo $url`"
['test "crio restore with bad state and pod removed"']="restore.bats case is not working: see `eval echo $url`"
['test "crio restore with bad state"']="restore.bats case is not working: see `eval echo $url`"
['test "crio restore with missing config.json"']="restore.bats case is not working: see `eval echo $url`"
['test "crio restore first not managing then managing"']="restore.bats case is not working: see `eval echo $url`"
['test "crio restore first managing then not managing"']="restore.bats case is not working: see `eval echo $url`"
['test "crio restore changing managing dir"']="restore.bats case is not working: see `eval echo $url`"
['test "crio restore"']="restore.bats case is not working: see `eval echo $url`"
['test "crio restore with pod stopped"']="restore.bats case is not working: see `eval echo $url`"
)
declare -A shm_size_skipCRIOTests=(
['test "check \/dev\/shm is changed"']="shm_size.bats case is not working: see `eval echo $url`"
)
declare -A timeout_skipCRIOTests=(
['test "should not clean up pod after timeout"']="timeout.bats case is not working: see `eval echo $url`"
['test "should not clean up container after timeout"']="timeout.bats case is not working: see `eval echo $url`"
['test "should clean up pod after timeout if request changes"']="timeout.bats case is not working: see `eval echo $url`"
['test "should clean up container after timeout if request changes"']="timeout.bats case is not working: see `eval echo $url`"
['test "should clean up pod after timeout if not re-requested"']="timeout.bats case is not working: see `eval echo $url`"
['test "should clean up container after timeout if not re-requested"']="timeout.bats case is not working: see `eval echo $url`"
['test "should not be able to operate on a timed out pod"']="timeout.bats case is not working: see `eval echo $url`"
['test "should not be able to operate on a timed out container"']="timeout.bats case is not working: see `eval echo $url`"
)
declare -A workloads_skipCRIOTests=(
['test "test workload gets configured to defaults"']="workloads.bats case is not working: see `eval echo $url`"
['test "test workload can override defaults"']="workloads.bats case is not working: see `eval echo $url`"
['test "test workload should not be set if not defaulted or specified"']="workloads.bats case is not working: see `eval echo $url`"
['test "test workload should not be set if annotation not specified"']="workloads.bats case is not working: see `eval echo $url`"
['test "test workload pod gets configured to defaults"']="workloads.bats case is not working: see `eval echo $url`"
['test "test workload can override pod defaults"']="workloads.bats case is not working: see `eval echo $url`"
['test "test workload pod should not be set if not defaulted or specified"']="workloads.bats case is not working: see `eval echo $url`"
['test "test workload pod should override infra_ctr_cpuset option"']="workloads.bats case is not working: see `eval echo $url`"
['test "test workload allowed annotation appended with runtime"']="workloads.bats case is not working: see `eval echo $url`"
['test "test workload allowed annotation works for pod"']="workloads.bats case is not working: see `eval echo $url`"
)
declare -A userns_annotation_skipCRIOTests=(
['test "userns annotation auto should succeed"']="userns_annotation.bats case is not working: see `eval echo $url`"
['test "userns annotation auto should map host run_as_user"']="userns_annotation.bats case is not working: see `eval echo $url`"
)
declare -A apparmor_skipCRIOTests=(
['test "reload config should succeed with 'apparmor_profile'"']='skip apparmor not enabled'
['test "reload config should fail with invalid 'apparmor_profile'"']='skip apparmor not enabled'
)
declare -A selinux_skipCRIOTests=(
['test "selinux skips relabeling if TrySkipVolumeSELinuxLabel annotation is present"']='skip not enforcing'
['test "selinux skips relabeling for super priviliged container"']='skip not enforcing'
);

# The following lists tests that should be skipped in specific cri-o versions.
# When adding a test here, you need to provide the version of cri-o where the
# bug was fixed. The script will skip this test in all previous versions.
declare -A ctr_fixedInCrioVersion=(
['test "privileged ctr device add"']="1.22"
['test "privileged ctr -- check for rw mounts"']="1.22"
['test "ctr execsync"']="1.22"
);
