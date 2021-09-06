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
    if host_arch == "x86_64"
      lv.machine_type = "q35"
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
    # makes effect.
    fedora.vm.provision "shell", reboot: true, inline: <<-SHELL
      sudo dnf install -y grubby
      # Set the kernel parameter to use cgroups v1.
      sudo grubby --update-kernel=ALL --args="systemd.unified_cgroup_hierarchy=0"
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
    ubuntu.vm.provision "shell", inline: <<-SHELL
      source "#{guest_env_file}"
      cd "${GOPATH}/src/github.com/kata-containers/tests"
      # Build the osbuilder with same distro as the host.
      export osbuilder_distro="ubuntu"
      sudo -E PATH=$PATH -H -u #{guest_user} bash -c '.ci/setup.sh'
    SHELL
  end
end
