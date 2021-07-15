#!/bin/bash
#
# Copyright (c) 2021 Red Hat
#
# SPDX-License-Identifier: Apache-2.0
#
# Implements the vm_runner interface for Vagrant.

_vagrant() {
    vagrant --machine-readable $@
}

is_engine_available() {
    command -v vagrant &>/dev/null
    # TODO: need to find a way to check the libvirt provider was
    # installed and is working.
}

is_vm_running() {
    local vm_name=$1
    local status="$(_vagrant status "$vm_name")"
    [[ "$status" =~ "${vm_name},state,running" ]]
}

vm_destroy() {
    local vm=$1
    vagrant destroy -f "$vm"
}

vm_start() {
    local vm=$1
    local force_destroy=${2:-"true"}
    if is_vm_running "$vm" && [ "$force_destroy" == "true" ];then
        vm_destroy "$vm"
    fi
    vagrant up "$vm"
}

vm_run_cmd() {
    local vm=$1
    shift 1
    vagrant ssh $vm -- $*
}

list_vms() {
    local vm_name=""
    _vagrant status | while read -r line; do
    if [[ "$line" =~ ^[0-9]+,.*,state, ]]; then
        echo "$line" | cut -d',' -f2 
    fi
    done
}
