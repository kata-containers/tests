#!/bin/bash
#
# Copyright (c) 2020 Red Hat, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
# This script installs the built kata-containers in the test cluster,
# and configure a runtime.

scripts_dir=$(dirname $0)
deployments_dir=${scripts_dir}/deployments
configs_dir=${scripts_dir}/configs

source ${scripts_dir}/../../lib.sh

# Wait all worker nodes reboot.
#
# Params:
#   $1 - timeout in seconds (default to 1800).
#
wait_for_reboot() {
	local delta="${1:-1800}"
	declare -A BOOTIDS
	local workers=($(oc get nodes | \
		awk '{if ($3 == "worker") { print $1 } }'))
	# Get the boot ID to compared it changed over time.
	for node in ${workers[@]}; do
		BOOTIDS[$node]=$(oc get -o jsonpath='{.status.nodeInfo.bootID}'\
			node/$node)
		echo "Wait $node reboot"
	done

	timer_start=$(date +%s)
	while [ ${#workers[@]} -gt 0 ]; do
		for i in ${!workers[@]}; do
			current_id=$(oc get \
				-o jsonpath='{.status.nodeInfo.bootID}' \
				node/${workers[i]})
			if [ "$current_id" != ${BOOTIDS[${workers[i]}]} ]; then
				echo "${workers[i]} rebooted"
				unset workers[i]
			fi
		done
		if [ $(($timer_start + $delta)) -lt $(date +%s) ]; then
			echo "Timeout: not all workers rebooted"
			return 1
		fi
		sleep 10
	done
}

oc project default

worker_nodes=$(oc get nodes |  awk '{if ($3 == "worker") { print $1 } }')
num_nodes=$(echo $worker_nodes | wc -w)
[ $num_nodes -ne 0 ] || \
	die "No worker nodes detected. Something is wrong with the cluster"

info "Set installing state annotation and label on all worker nodes"
for node in $worker_nodes; do
	info "Deploy kata in worker node $node"
	oc annotate --overwrite nodes $node \
		kata-install-daemon.v1.openshift.com/state=installing
	oc label --overwrite node $node kata-deploy=true
done

info "Applying the kata installer daemonset"
if [ -z "$KATA_INSTALLER_IMG" ]; then
	# The yaml file uses $IMAGE_FORMAT which gives the
	# registry/image_stream:image format
	export KATA_INSTALLER_IMG=$(echo $IMAGE_FORMAT"kata-installer" \
		| envsubst)
fi
envsubst < ${deployments_dir}/daemonset_kata-installer.yaml.in | oc apply -f -

oc get pods
oc get ds
ds_pods=($(oc get pods | awk '{if ($1 ~ "kata-deploy") { print $1 } }'))
cnt=5
while [[ ${#ds_pods[@]} -gt 0 && $cnt -ne 0 ]]; do
	sleep 120
	for i in ${!ds_pods[@]}; do
		info "Check daemonset ${ds_pods[i]} is running"
		rc=$(oc exec ${ds_pods[i]} -- cat /tmp/kata_install_status 2> \
			/dev/null)
		if [ -n "$rc" ]; then
			info "Finished with status: $rc"
			oc describe pods ${ds_pods[i]}
			oc logs ${ds_pods[i]}
			unset ds_pods[i]
		else
			info "Running"
		fi
	done
	cnt=$((cnt-1))
done

if [ $cnt -eq 0 ]; then
	for p in ${ds_pods[@]}; do
		info "daemonset $p did not finish"
		oc describe pods $p
		oc logs $p
	done
	die "Kata Containers seems not installed on some nodes"
fi

# Finally remove the installer daemonset
info "Deleting the kata installer daemonset"
oc delete -f ${deployments_dir}/daemonset_kata-installer.yaml.in

# Apply the CRI-O configuration
info "Configuring kata runtime for CRI-O"
if [ -z "$KATA_CRIO_CONF_BASE64" ]; then
	export KATA_CRIO_CONF_BASE64=$(echo \
		$(cat $configs_dir/crio_kata.conf|base64) | sed -e 's/\s//g')
fi
envsubst < ${deployments_dir}/machineconfig_kata_runtime.yaml.in | oc apply -f -
oc get -f ${deployments_dir}/machineconfig_kata_runtime.yaml.in || \
	die "Kata machineconfig not found"

# The machineconfig which installs the kata drop-in in CRI-O will trigger a
# worker reboot.
wait_for_reboot

# Add a runtime class for kata
info "Adding the kata runtime class"
oc apply -f ${deployments_dir}/runtimeclass_kata.yaml
oc get runtimeclass/kata || die "kata runtime class not found"

# Set SELinux to permissive mode
info "Configuring SELinux"
if [ -z "$SELINUX_CONF_BASE64" ]; then
	export SELINUX_CONF_BASE64=$(echo \
		$(cat $configs_dir/selinux.conf|base64) | sed -e 's/\s//g')
fi
envsubst < ${deployments_dir}/machineconfig_selinux.yaml.in | oc apply -f -
oc get machineconfig/51-kata-selinux || die "SELinux machineconfig not found"
# The new SELinux configuration will trigger another reboot.
wait_for_reboot

# At this point kata is installed on workers
info "Set state annotation to installed on all worker nodes"
for node in $worker_nodes; do
	oc annotate --overwrite nodes $node \
		kata-install-daemon.v1.openshift.com/state=installed
done
