# Copyright (c) 2021 Red Hat, Inc.
#
# SPDX-License-Identifier: Apache-2.0
#
# This is a Vagrant configuration file.
#

# -*- mode: ruby -*-
# vi: set ft=ruby :

# Read the Kata Containers CI job from the CI_JOB environment variable.
job = ENV['CI_JOB'] || ""
guest_user = 'vagrant'
guest_home_dir = '/home/vagrant'
# The file on the guest where environment variables are going to be set
# to export.
guest_env_file = guest_home_dir + '/ci_job_env'
host_arch = `uname -m`.strip

# All Vagrant configuration is done below. The "2" in Vagrant.configure
# configures the configuration version (we support older styles for
# backwards compatibility). Please don't change it unless you know what
# you're doing.
Vagrant.configure("2") do |config|

  config.trigger.before [:up, :ssh] do |trigger|
    if ENV['GOPATH'] == nil
      trigger.warn = "You must export the GOPATH environment variable"
      trigger.abort = true
    end
  end

  # By default vagrant sync the current directory. Let's disabled it because the directory
  # will be synced later to the proper destination.
  config.vm.synced_folder ".", "/vagrant", disabled:true
  config.vm.synced_folder ".", "#{guest_home_dir}/go/src/github.com/kata-containers/tests", type:"rsync"
  config.vm.synced_folder "#{ENV['GOPATH']}/src/github.com/kata-containers/kata-containers",
    "#{guest_home_dir}/go/src/github.com/kata-containers/kata-containers", type:"rsync"

  config.vm.provider "libvirt" do |lv|
    lv.driver = "kvm"
    lv.cpus = "4"
    lv.memory = "8192"
    # Domains on Libvirt will be created with the following prefix.
    lv.default_prefix = "kata_containers_test-"
    if host_arch == "x86_64"
      lv.machine_type = "q35"
    end
    # The VM needs one additional virtio-net device and iommu enabled
    # for the vfio tests.
    if host_arch == "x86_64"
      lv.qemuargs :value => "-machine"
      lv.qemuargs :value => "kernel-irqchip=split"
      lv.qemuargs :value => "-device"
      lv.qemuargs :value => "intel-iommu,intremap=on,caching-mode=on,device-iotlb=on"
      # Currently the vfio test picks the last virtio-net device from lspci's
      # output. Here we add the device in a PCIe root port with higher slot
      # number on the hope it will be the last in the list.
      lv.qemuargs :value => "-device"
      lv.qemuargs :value => "pcie-root-port,port=0x16,chassis=7,id=pcie.7,multifunction=on,bus=pcie.0,addr=0xF"
      lv.qemuargs :value => "-netdev"
      lv.qemuargs :value => "user,id=vfio1"
      lv.qemuargs :value => "-device"
      lv.qemuargs :value => "virtio-net-pci,netdev=vfio1,bus=pcie.7,disable-legacy=on,disable-modern=off,iommu_platform=on,ats=on"
    end
  end

  # Shared provision script.
  config.vm.provision "shell", env: {"CI_JOB" => job}, inline: <<-SHELL

    export GOPATH="#{guest_home_dir}/go"
    # The repositories were copied to the vagrant user's home by the root
    # user. So let's fix the files ownership.
    chown -R #{guest_user}:#{guest_user} "${GOPATH}"
    kata_tests_repo_dir="${GOPATH}/src/github.com/kata-containers/tests"

    env_file="#{guest_env_file}"
    sudo -E PATH=$PATH -H -u #{guest_user} \
    cat <<-EOF > ${env_file}
export GOPATH="$GOPATH"
export PATH="/usr/local/go/bin:\$GOPATH/bin:\$PATH"
export CI="true"
export CI_JOB="$CI_JOB"
pushd $kata_tests_repo_dir &>/dev/null
source .ci/ci_job_flags.sh
popd &>/dev/null
EOF

    source ${env_file}

    # Customize the .bashrc so that it will have the variables exported
    # after log-in.
    sudo -E PATH=$PATH -u #{guest_user} \
    echo "cd $kata_tests_repo_dir" >> #{guest_home_dir}/.bashrc
    sudo -E PATH=$PATH -u #{guest_user} \
    echo "source $env_file" >> #{guest_home_dir}/.bashrc
  SHELL

  config.vm.define "fedora", autostart: false do |fedora|
    fedora.vm.box = "fedora/32-cloud-base"
    # Fedora is required to reboot so that the change to cgroups v1
    # and kernel arguments make effect.
    fedora.vm.provision "shell", reboot: true, inline: <<-SHELL
      # Set the kernel parameter to use cgroups v1.
      sudo grubby --update-kernel=ALL --args="systemd.unified_cgroup_hierarchy=0"
      # Set iommu's kernel parameters for vfio tests.
      source "#{guest_env_file}"
      if [ "${CI_JOB}" == "VFIO" ]; then
        grubby --update-kernel=ALL --args="intel_iommu=on iommu=pt"
      fi
    SHELL

    fedora.vm.provision "shell", inline: <<-SHELL
      source "#{guest_env_file}"
      cd "${GOPATH}/src/github.com/kata-containers/tests"
      # Build the osbuilder with same distro as the host.
      export osbuilder_distro="fedora"
      sudo -E PATH=$PATH -H -u #{guest_user} bash -c '.ci/setup.sh'
    SHELL
  end

  config.vm.define "ubuntu", autostart: false do |ubuntu|
    ubuntu.vm.box = "generic/ubuntu2004"
    if job == "VFIO"
      ubuntu.vm.provision "shell", reboot: true, inline: <<-SHELL
        # Set iommu's kernel parameters for vfio tests. That requires a reboot.
        sed -i 's/\\(GRUB_CMDLINE_LINUX_DEFAULT\\)="\\(.*\\)"/\\1="\\2 intel_iommu=on iommu=pt"/' /etc/default/grub
        update-grub
      SHELL
    end

    ubuntu.vm.provision "shell", inline: <<-SHELL
      source "#{guest_env_file}"
      cd "${GOPATH}/src/github.com/kata-containers/tests"
      # Build the osbuilder with same distro as the host.
      export osbuilder_distro="ubuntu"
      sudo -E PATH=$PATH -H -u #{guest_user} bash -c '.ci/setup.sh'
    SHELL
  end
end
