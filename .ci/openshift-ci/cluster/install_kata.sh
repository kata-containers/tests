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

# Set to 'yes' if you want to configure SELinux to permissive on the cluster
# workers.
#
SELINUX_PERMISSIVE=${SELINUX_PERMISSIVE:-no}

# The daemonset name.
#
export DAEMONSET_NAME="kata-deploy"

# The label attached to the nodes which should have Kata Containers installed.
#
export DAEMONSET_LABEL="kata-deploy"

# Wait all worker nodes reboot.
#
# Params:
#   $1 - timeout in seconds (default to 900).
#
wait_for_reboot() {
	local delta="${1:-900}"
	local sleep_time=60
	declare -A BOOTIDS
	local workers=($(oc get nodes | \
		awk '{if ($3 == "worker") { print $1 } }'))
	# Get the boot ID to compared it changed over time.
	for node in ${workers[@]}; do
		BOOTIDS[$node]=$(oc get -o jsonpath='{.status.nodeInfo.bootID}'\
			node/$node)
		echo "Wait $node reboot"
	done

	echo "Set timeout to $delta seconds"
	timer_start=$(date +%s)
	while [ ${#workers[@]} -gt 0 ]; do
		sleep $sleep_time
		now=$(date +%s)
		if [ $(($timer_start + $delta)) -lt $now ]; then
			echo "Timeout: not all workers rebooted"
			return 1
		fi
		echo "Checking after $(($now - $timer_start)) seconds"
		for i in ${!workers[@]}; do
			current_id=$(oc get \
				-o jsonpath='{.status.nodeInfo.bootID}' \
				node/${workers[i]})
			if [ "$current_id" != ${BOOTIDS[${workers[i]}]} ]; then
				echo "${workers[i]} rebooted"
				unset workers[i]
			fi
		done
	done
}

# Print useful information for debugging.
#
# Params:
#   $1 - the pod name
debug_pod() {
	local pod="$1"
	info "Debug pod: ${pod}"
	oc describe pods "$pod"
        oc logs "$pod"
}

oc project default

worker_nodes=$(oc get nodes |  awk '{if ($3 == "worker") { print $1 } }')
num_nodes=$(echo $worker_nodes | wc -w)
[ $num_nodes -ne 0 ] || \
	die "No worker nodes detected. Something is wrong with the cluster"

info "Set installing state annotation and label on all worker nodes"
for node in $worker_nodes; do
	info "Deploy kata Containers in worker node $node"
	oc annotate --overwrite nodes $node \
		kata-install-daemon.v1.openshift.com/state=installing
	oc label --overwrite node $node "${DAEMONSET_LABEL}=true"
done

info "Applying the Kata Containers installer daemonset"
if [ -z "$KATA_INSTALLER_IMG" ]; then
	# The yaml file uses $IMAGE_FORMAT which gives the
	# registry/image_stream:image format
	export KATA_INSTALLER_IMG=$(echo $IMAGE_FORMAT"kata-installer" \
		| envsubst)
fi
envsubst < ${deployments_dir}/daemonset_kata-installer.yaml.in | oc apply -f -

oc get pods
oc get ds
ds_pods=($(oc get pods | awk -v ds=$DAEMONSET_NAME '{if ($1 ~ ds) { print $1 } }'))
broken=0
broken_ds_pods=()
cnt=5
while [[ ${#ds_pods[@]} -gt 0 && $cnt -ne 0 ]]; do
	sleep 120
	for i in ${!ds_pods[@]}; do
		info "Check daemonset ${ds_pods[i]} is running"
		rc=$(oc exec ${ds_pods[i]} -- cat /tmp/kata_install_status 2> \
			/dev/null) || broken=1
		if [ $broken -eq 1 ]; then
			info "Daemonset seems broken"
			broken_ds_pods+=(${ds_pods[i]})
			unset ds_pods[i]
			broken=0
		elif [ -n "$rc" ]; then
			info "Finished with status: $rc"
			debug_pod "${ds_pods[i]}"
			unset ds_pods[i]
		else
			info "Running"
		fi
	done
	cnt=$((cnt-1))
done

if [[ $cnt -eq 0 || ${#broken_ds_pods[@]} -gt 0 ]]; then
	for p in $ds_pods $broken_ds_pods; do
		info "daemonset $p did not finish or is broken"
		debug_pod "$p"
	done
	die "Kata Containers seems not installed on some nodes"
fi

# Finally remove the installer daemonset
info "Deleting the Kata Containers installer daemonset"
oc delete ds/${DAEMONSET_NAME}

# Apply the CRI-O configuration
info "Configuring Kata Containers runtime for CRI-O"
if [ -z "$KATA_CRIO_CONF_BASE64" ]; then
	export KATA_CRIO_CONF_BASE64=$(echo \
		$(cat $configs_dir/crio_kata.conf|base64) | sed -e 's/\s//g')
fi
envsubst < ${deployments_dir}/machineconfig_kata_runtime.yaml.in | oc apply -f -
oc get -f ${deployments_dir}/machineconfig_kata_runtime.yaml.in || \
	die "kata machineconfig not found"

# The machineconfig which installs the kata drop-in in CRI-O will trigger a
# worker reboot.
wait_for_reboot

# Add a runtime class for kata
info "Adding the kata runtime class"
oc apply -f ${deployments_dir}/runtimeclass_kata.yaml
oc get -f ${deployments_dir}/runtimeclass_kata.yaml || die "kata runtime class not found"

# Set SELinux to permissive mode
if [ ${SELINUX_PERMISSIVE} == "yes" ]; then
	info "Configuring SELinux"
	if [ -z "$SELINUX_CONF_BASE64" ]; then
		export SELINUX_CONF_BASE64=$(echo \
			$(cat $configs_dir/selinux.conf|base64) | \
			sed -e 's/\s//g')
	fi
	envsubst < ${deployments_dir}/machineconfig_selinux.yaml.in | \
		oc apply -f -
	oc get machineconfig/51-kata-selinux || \
		die "SELinux machineconfig not found"
	# The new SELinux configuration will trigger another reboot.
	wait_for_reboot
fi

# At this point kata is installed on workers
info "Set state annotation to installed on all worker nodes"
for node in $worker_nodes; do
	oc annotate --overwrite nodes $node \
		kata-install-daemon.v1.openshift.com/state=installed
done
