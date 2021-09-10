#!/bin/bash
#
# Copyright (c) 2021 Red Hat, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
cidir="$(dirname $(readlink -f "$0"))"

# Print message to stderr (add the 'ERROR:' prefix) and exit 1.
die() {
	echo -e "ERROR: $*" >&2
	exit 1
}

usage() {
	cat <<-EOF
		This script helps you to clean up the VMs and Vagrant's control
		directories.
		By default it will attempt to destroy all VMs. For additionally
		remove control directories use one or more of the flags shown
		below.

		Use: $0 [-g] [-h] [-l] [-n VM_NAME], where
		  -g: also remove the vagrant's global directory (~/.vagrant.d)
		      Implies -l.
		  -h: print this help.
		  -l: also remove the vagrant's local directory.
		  -n: destroy the VM. Do not remove any vagrant's directories.

		Caution: only use the -g flag if you know what you are doing.
	EOF
}

# Return the VM names.
get_vms() {
	local vms=()
	for vm in $(vagrant status --machine-readable | grep 'metadata,provider'); do
		vms+=($(awk -F, '{ print $2}' <<< "$vm"))
	done
	echo ${vms[@]}
}

# Use vagrant to gentle destroy the VM.
#
# Parameters:
#   $1 - the VM name
vagrant_destroy() {
	local vm="$1"
	if vagrant destroy --force "$vm"; then
		echo "VM '$vm' destroyed: OK"
	else
		echo "VM '$vm' destroyed: FAILED"
		return 1
	fi
}

# Remove the domain from libvirt.
#
# Parameters:
#   $1 - the VM name
libvirt_cleanup() {
	local vm="$1"
	# TODO: find a way to discovery the domain prefix.
	local prefix="tests_"
	local domain="${prefix}${vm}"
	if ! virsh dominfo "$vm" &> /dev/null; then
		echo "Domain '$domain' does not exist. Nothing to do."
	elif virsh destroy "$domain" && virsh undefine "$domain"; then
		echo "Domain '$domain' cleaned on libvirt: OK"
	else
		echo "Domain '$domain' cleaned on libvirt: FAILED"
		return 1
	fi
}

# Entrypoint function to remove the VM. In case it cannot be destroyed with
# vagrant, it will forcibly remove the domain from libvirt.
#
# Parameters:
#   $1 - the VM name
vm_wipeout() {
	local vm="$1"
	if ! vagrant status "$vm" &>/dev/null; then
		echo "VM '$vm' does not exist. Nothing to do."
		return 0
	fi

	vagrant_destroy "$vm"
	if [ $? -ne 0 ]; then
		echo "WARN: Attempt to clean up the domain on libvirt"
		libvirt_cleanup "$vm"
	fi
}

# Remove vagrant's control directories, whether local or global.
#
# Parameters:
#  $1 - set to 1 to remove the global directory as well. Defaults to 0.
cfgs_wipeout() {
	local global=${1:-0}
	local local_cfg="${cidir}/../.vagrant"
	local global_cfg="${HOME}/.vagrant.d"

	echo "Remove vagrant's local directory: $local_cfg"
	rm -rf "$local_cfg"
	if [ "$global" -eq 1 ]; then
		echo "Remove vagrant's global directory: $global_cfg"
		rm -rf "$global_cfg"
	fi
}

main() {
	local vms=()
	local ret=0
	local single_vm=""
	local local_cfg=0
	local global_cfg=0
	while getopts "aghln:" OPT; do
		case $OPT in
			g) global_cfg=1;;
			h) usage; exit 0;;
			l) local_cfg=1;;
			n) single_vm="$OPTARG";;
			*) usage; exit 1;;
		esac
	done

	command -v vagrant &>/dev/null || \
		die "missing 'vagrant' command. Run $0 -h for help."

	# If there is any inconsistency on Vagrantfile then it exits here.
	vagrant validate || \
		die "Vagrantfile cannot be validated. Bailing out.\n" \
		"Tip: ensure that GOPATH is exported in your environment."

	if [ -n "$single_vm" ]; then
		vm_wipeout "$single_vm" || ret=$?
	else
		for vm in $(get_vms); do
			vm_wipeout $vm || ret=$?
		done

		[ $ret -eq 0 ] || \
			die "Failed the removal of some VM."

		# Only allow the removal of vagrant's configuration files in
		# case the user wants to destroy all VMs and everything went
		# well, so to avoid leaking resources.
		if [[ "$local_cfg" -eq 1 || "$global_cfg" -eq 1 ]]; then
			if [ $ret -ne 0 ]; then
				echo "WARN: vagrant's directories are kept."
			else
				cfgs_wipeout "$global_cfg" || ret=$?
			fi
		fi
	fi
	return $ret
}

main $@
