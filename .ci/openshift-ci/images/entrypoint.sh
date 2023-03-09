#!/bin/bash
#
# Copyright (c) 2020 Red Hat Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
# Synchronize the kata-containers installation with in the host filesystem.
#
set -e
set -o nounset

install_status=1

SRC="${PWD}/_out/build_install"

# Expect the host filesystem to be mounted in following path.
HOST_MOUNT=/host

# Overwrite the default QEMU path on configuration.toml
QEMU_PATH=${QEMU_PATH:-}
# Overwrite the default Kernel path on configuration.toml
USE_HOST_KERNEL=${USE_HOST_KERNEL:-no}

terminate()
{
	# Sending a termination message. Can be used by an orchestrator that
	# will look into this file to check the installation has finished
	# and is good.
	#
	echo "INFO: the installation status is $install_status"
	echo "$install_status" >> /tmp/kata_install_status

	# By using it in an openshift daemonset it should spin forever until an
	# orchestrator kills it.
	#
	echo "INFO: spinning until the orchestrator kill this process"
	tail -f /dev/null
}

# Set the QEMU path on configuration.toml to $QEMU_PATH, also update
# virtiofsd's path.
update_qemu_path()
{
	local toml="${SRC}/opt/kata/share/defaults/kata-containers/configuration.toml"
	# Make a copy of the original file, it can help with debugging.
	cp -f "$toml" "${toml}.orig"
	sed --follow-symlinks -i 's#/opt/kata/bin/qemu-system-x86_64#'${QEMU_PATH}'#g' "$toml"
	# Assume virtiofsd is located at same directory of QEMU.
	local virtiofsd_path="$(dirname $QEMU_PATH)/virtiofsd"
	sed --follow-symlinks -i 's#/opt/kata/libexec/kata-qemu/virtiofsd#'$virtiofsd_path'#g' \
		"$toml"
}

# Set the Kernel path on configuration.toml to the host's.
#
update_kernel_path()
{
	local toml="${SRC}/opt/kata/share/defaults/kata-containers/configuration.toml"
	local kernel_path="/lib/modules/$(uname -r)/vmlinuz"
	sed --follow-symlinks -i 's#^kernel = ".*"#kernel = "'${kernel_path}'"#g' "$toml"
}

# In case the initrd was not created in a build root which kernel version
# mismatch with the one of the OpenShift worker node, this function will
# update the initrd accordingly.
update_initrd_kernel_modules()
{
	local initrd_path="${SRC}/opt/kata/share/kata-containers/kata-containers-initrd.img"
	local moddir="${HOST_MOUNT}/lib/modules"
	# Modules directory relative to initrd root directory.
	local initrd_moddir="usr/lib/modules"
	local kernel=$(ls ${moddir} | head -1)
	local rootfs_dir="${PWD}/rootfs"

	if lsinitrd "${initrd_path}" | grep -q "${initrd_moddir}/${kernel}"; then
		echo "initrd contain ${kernel} modules. Nothing to do."
		return
	fi

	echo "Going to update ${initrd_path} for kernel ${kernel}"
	rm -rf "${rootfs_dir}"
	mkdir -p "${rootfs_dir}"

	cat "${initrd_path}" | cpio --extract --preserve-modification-time \
		--make-directories --directory="${rootfs_dir}"
	cp -ar "${moddir}/${kernel}" "${rootfs_dir}/${initrd_moddir}" || true

	# Make a copy of the old initrd just in case debug is needed.
	cp ${initrd_path} ${initrd_path}.old.$$
	( cd "${rootfs_dir}" && find . | cpio -H newc -o | gzip -9 ) > ${initrd_path}
}

if [ "$(id -u)" -ne 0 ]; then
	echo "ERROR: $0 must be executed by privileged user"
	terminate
fi

[ -n "$QEMU_PATH" ] && update_qemu_path

# Configure to use the host kernel.
if [ "$USE_HOST_KERNEL" == "yes" ]; then
	update_kernel_path
	update_initrd_kernel_modules
fi

# Some files are copied over /usr which on Red Hat CoreOS (rhcos) is mounted
# read-only by default. So re-mount it as read-write, otherwise files won't
# get copied.
echo "INFO: re-mount ${HOST_MOUNT}/usr on rw mode"
mount -o remount,rw "${HOST_MOUNT}/usr"

# The host's '/opt' and '/usr/local' are symlinks to, respectively, '/var/opt'
# and '/var/usrlocal'. Adjust the installation files accordingly.
#
cd $SRC
if [ -d 'opt' ]; then
	mkdir -p var
	mv opt var
fi

if [ -d "usr/local" ]; then
	mkdir -p var
	mv usr/local var/usrlocal
fi

# Copy the installation over the host filesystem.
echo "INFO: copy the Kata Containers installation over $HOST_MOUNT"
rsync -O -a . "$HOST_MOUNT"

# Ensure the binaries are searcheable via PATH. Notice it expects that
# kata has been built with PREFIX=/opt/kata.
#
chroot "$HOST_MOUNT" sh -c 'for t in /opt/kata/bin/*; do ln --force -s "$t" /var/usrlocal/bin/; done'

# Check the installation is good (or not).
echo "INFO: run kata-check to check the installation is fine"
chroot "$HOST_MOUNT" /opt/kata/bin/kata-runtime kata-check
install_status=$?

terminate
