#!/bin/bash
#
# Copyright (c) 2020 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

# Run the .ci/jenkins_job_build.sh script in a VM
# that supports VFIO, then run VFIO functional tests

set -x
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

cidir=$(dirname "$0")

source /etc/os-release || source /usr/lib/os-release
source "${cidir}/lib.sh"

http_proxy=${https_proxy:-}
https_proxy=${https_proxy:-}
vm_ip="127.0.15.1"
vm_port="10022"
data_dir="${HOME}/vfio-test"
ssh_key_file="${data_dir}/key"
arch=$(uname -i)
artifacts_dir="${WORKSPACE}/artifacts"

mkdir -p "${data_dir}"

trap cleanup EXIT

kill_vms() {
	sudo killall -9 qemu-system-${arch}
}

cleanup() {
	mkdir -p ${artifacts_dir}
	sudo chown -R ${USER} ${artifacts_dir}
	scp_vm ${artifacts_dir}/* ${artifacts_dir} || true
	kill_vms
}

create_ssh_key() {
	rm -f "${ssh_key_file}"
	ssh-keygen -f "${ssh_key_file}" -t rsa -N ""
}

create_meta_data() {
	file="$1"
	cat <<EOF > "${file}"
{
  "uuid": "d1b4aafa-5d75-4f9c-87eb-2ceabe110c39",
  "hostname": "test"
}
EOF
}

create_user_data() {
	file="$1"
	ssh_pub_key_file="$2"

	ssh_pub_key="$(cat "${ssh_pub_key_file}")"
	dnf_proxy=""
	docker_proxy=""
	docker_user_proxy=""
	environment=$(env | egrep "ghprb|WORK|KATA|GIT|JENKINS|_PROXY|_proxy" | \
	                    sed -e "s/'/'\"'\"'/g" \
	                        -e "s/\(^[[:alnum:]_]\+\)=/\1='/" \
	                        -e "s/$/'/" \
	                        -e 's/^/    export /')

	if [ -n "${http_proxy}" ] && [ -n "${https_proxy}" ]; then
		dnf_proxy="dnf:
  https_proxy: ${https_proxy}
  proxy: ${http_proxy}"
		docker_proxy='[Service]
    Environment="HTTP_PROXY='${http_proxy}'" "HTTPS_PROXY='${https_proxy}'" "NO_PROXY='${no_proxy}'"'
		docker_user_proxy='{"proxies": { "default": {
    "httpProxy": "'${http_proxy}'",
    "httpsProxy": "'${https_proxy}'",
    "noProxy": "'${no_proxy}'"
    } } }'
	fi

	tests_go_path="/home/${USER}/go/src/${tests_repo}"

	cat <<EOF > "${file}"
#cloud-config
${dnf_proxy}
package_upgrade: false
packages:
- git
- make
- pciutils
runcmd:
- chown -R ${USER}:${USER} /home/${USER}
- touch /.done
users:
- gecos: User
  gid: "1000"
  lock-passwd: true
  name: ${USER}
  shell: /bin/bash
  ssh-authorized-keys:
  - ${ssh_pub_key}
  sudo: ALL=(ALL) NOPASSWD:ALL
  uid: "1000"
write_files:
- content: |
${environment}
  path: /etc/environment
- content: |
    ${docker_proxy}
  path: /etc/systemd/system/docker.service.d/http-proxy.conf
- content: |
    ${docker_user_proxy}
  path: ${HOME}/.docker/config.json
- content: |
    set -x
    set -o errexit
    set -o nounset
    set -o pipefail
    set -o errtrace
    . /etc/environment
    for i in \$(seq 1 20); do
        [ -f /.done ] && break
        echo "waiting for cloud-init to finish"
        sleep 10;
    done

    export VFIO_CI=yes
    export CRIO=no
    export CRI_CONTAINERD=no
    export KUBERNETES=no
    export OPENSHIFT=no
    export CI_JOB="VFIO"
    export CI="true"
    export GOPATH=\${WORKSPACE}/go
    export PATH=\${GOPATH}/bin:/usr/local/go/bin:/usr/sbin:\${PATH}
    export GOROOT="/usr/local/go"
    export ghprbPullId
    export ghprbTargetBranch

    # Make sure the packages were installed
    # Sometimes cloud-init is unable to install them
    sudo dnf makecache
    sudo dnf install -y git make pciutils

    tests_repo_dir="\${GOPATH}/src/github.com/kata-containers/tests"
    mkdir -p "\${tests_repo_dir}"
    git clone https://github.com/kata-containers/tests.git "\${tests_repo_dir}"
    cd "\${tests_repo_dir}"

    trap "cd \${tests_repo_dir}; sudo -E PATH=\$PATH .ci/teardown.sh ${artifacts_dir} || true; sudo chown -R \${USER} ${artifacts_dir}" EXIT

    if echo \${GIT_URL} | grep -q tests; then
        pr_number="\${ghprbPullId}"
        pr_branch="PR_\${pr_number}"
        git fetch origin "pull/\${pr_number}/head:\${pr_branch}"
        git checkout "\${pr_branch}"
        git rebase "origin/\${ghprbTargetBranch}"
    fi

    sudo -E PATH=\$PATH .ci/jenkins_job_build.sh "\$(echo \${GIT_URL} | sed -e 's|https://||' -e 's|.git||')"

  path: /home/${USER}/run.sh
  permissions: '0755'
EOF
}

create_config_iso() {
	iso_file="$1"
	ssh_pub_key_file="${ssh_key_file}.pub"
	iso_data_dir="${data_dir}/d"
	meta_data_file="${iso_data_dir}/openstack/latest/meta_data.json"
	user_data_file="${iso_data_dir}/openstack/latest/user_data"

	mkdir -p $(dirname "${user_data_file}")

	create_meta_data "${meta_data_file}"
	create_user_data "${user_data_file}" "${ssh_pub_key_file}"

	[ -f "${iso_file}" ] && rm -f "${iso_file}"

	xorriso -as mkisofs -R -V config-2 -o "${iso_file}" "${iso_data_dir}"
}

pull_fedora_cloud_image() {
	fedora_img="$1"
	fedora_img_cache="${fedora_img}.cache"
	fedora_version=30

	if [ ! -f "${fedora_img_cache}" ]; then
		curl -Lk "https://download.fedoraproject.org/pub/fedora/linux/releases/${fedora_version}/Cloud/${arch}/images/Fedora-Cloud-Base-${fedora_version}-1.2.${arch}.raw.xz" -o "${fedora_img_cache}.xz"
		xz -f -d "${fedora_img_cache}.xz"
		sync
	fi

	cp -a "${fedora_img_cache}" "${fedora_img}"
	sync

	# setup cloud image
	sudo losetup -D
	loop=$(sudo losetup --show -Pf "${fedora_img}")
	sudo mount "${loop}p1" /mnt

	# disable selinux
	sudo sed -i 's/^SELINUX=.*/SELINUX=disabled/g' /mnt/etc/selinux/config

	# add intel_iommu=on to the guest kernel command line
	sudo sed -i 's|default_kernelopts="|default_kernelopts="intel_iommu |g' /mnt/boot/grub2/grub.cfg
	sudo sed -i 's|kernelopts=|kernelopts=intel_iommu=on |g' /mnt/boot/grub2/grubenv

	# cleanup
	sudo umount -R /mnt/
	sudo losetup -d "${loop}"

	qemu-img resize -f raw "${fedora_img}" +10G
}

run_vm() {
	image="$1"
	config_iso="$2"
	disable_modern="off"
	hostname="$(hostname)"
	memory="16384M"
	cpus=4

	/usr/bin/qemu-system-${arch} -m "${memory}" -smp cpus="${cpus}" -cpu host,host-phys-bits -machine q35,accel=kvm,kernel_irqchip=split \
	   -device intel-iommu,intremap=on,caching-mode=on,device-iotlb=on \
	   -drive file=${image},if=virtio,aio=threads,format=raw \
	   -drive file=${config_iso_file},if=virtio,media=cdrom \
	   -daemonize -enable-kvm -device virtio-rng-pci -display none -vga none \
	   -netdev user,hostfwd=tcp:${vm_ip}:${vm_port}-:22,hostname="${hostname}",id=net0 \
	   -device virtio-net-pci,netdev=net0,disable-legacy=on,disable-modern="${disable_modern}",iommu_platform=on,ats=on \
	   -netdev user,id=net1 \
	   -device virtio-net-pci,netdev=net1,disable-legacy=on,disable-modern="${disable_modern}",iommu_platform=on,ats=on
}

install_dependencies() {
	case "${ID}" in
		ubuntu|debian)
			# cloud image dependencies
			deps=(xorriso curl qemu-utils openssh-client)

			# QEMU dependencies
			deps+=(libcap-dev libattr1-dev libcap-ng-dev librbd-dev gcc pkg-config libglib2.0-dev libpixman-1-dev psmisc)

			sudo apt-get update
			sudo apt-get install -y ${deps[@]}
			;;
		fedora)
			# cloud image dependencies
			deps=(xorriso curl qemu-img openssh)

			# QEMU dependencies
			deps+=(libcap-devel libattr-devel libcap-ng-devel librbd-devel gcc glib2-devel pixman-devel psmisc)

			sudo dnf install -y ${deps[@]}
			;;

		"*")
			die "Unsupported distro: ${ID}"
			;;
	esac

	# Build and Install QEMU
	qemu_version="4.2.0"
	qemu_dir="${data_dir}/qemu-${qemu_version}"
	qemu_tar_file="${data_dir}/qemu-${qemu_version}.tar.xz"

	rm -rf "${qemu_dir}"
	mkdir -p "${qemu_dir}"

	pushd "${qemu_dir}"
	[ ! -f "${qemu_tar_file}" ] && curl -Lk https://download.qemu.org/qemu-${qemu_version}.tar.xz -o "${qemu_tar_file}"
	tar --strip-components=1 -xf "${qemu_tar_file}"
	curl -LOk https://raw.githubusercontent.com/kata-containers/packaging/master/scripts/configure-hypervisor.sh
	bash configure-hypervisor.sh qemu | sed -e 's|--disable-slirp||' -e 's|--enable-libpmem||' | xargs ./configure
	make -j$(nproc)
	sudo make install
	popd
}

ssh_vm() {
	cmd=$@
	ssh -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -i "${ssh_key_file}" -p "${vm_port}" "${USER}@${vm_ip}" "${cmd}"
}

scp_vm() {
	guest_src=$1
	host_dest=$2
	scp -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -i "${ssh_key_file}" -P "${vm_port}" ${USER}@${vm_ip}:${guest_src} ${host_dest}
}

wait_for_vm() {
	for i in $(seq 1 30); do
		if ssh_vm true; then
			return 0
		fi
		info "waiting for VM to start"
		sleep 5
	done
	return 1
}

main() {
	config_iso_file="${data_dir}/config.iso"
	fedora_img="${data_dir}/image.img"

	install_dependencies

	create_ssh_key

	create_config_iso "${config_iso_file}"

	pull_fedora_cloud_image "${fedora_img}"

	for i in $(seq 1 5); do
		run_vm "${fedora_img}" "${config_iso_file}"
		if wait_for_vm; then
			break
		fi
		info "Couldn't connect to the VM. Stopping VM and starting a new one."
		kill_vms
	done

	ssh_vm "/home/${USER}/run.sh"
}

main $@
