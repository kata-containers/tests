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
guest_home_dir = '/home/vagrant'

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
  end

  # Shared provision script.
  config.vm.provision "shell", env: {"CI_JOB" => job}, inline: <<-SHELL

    export GOPATH="#{guest_home_dir}/go"
    kata_tests_repo_dir="${GOPATH}/src/github.com/kata-containers/tests"

    env_file="#{guest_home_dir}/ci_job_env"
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
    echo "cd $kata_tests_repo_dir" >> #{guest_home_dir}/.bashrc
    echo "source $env_file" >> #{guest_home_dir}/.bashrc

    distro=$(source /etc/os-release; echo $ID)
    case "$distro" in
      "fedora")
        # Fedora >= 32 Kernel comes configured with cgroup v2 by default.
        # This switches back to cgroup v1. It requires a reboot.
        sudo dnf install -y grubby
        sudo grubby --update-kernel=ALL --args="systemd.unified_cgroup_hierarchy=0"
        ;;
      "ubuntu")
        # TODO: redis-server package fails to install if IPv6 is disabled. Move this
        # code to the setup script.
        if [[ $(sudo sysctl -n net.ipv6.conf.all.disable_ipv6) -eq 1 ]]; then
          sudo sysctl -w net.ipv6.conf.all.disable_ipv6=0
          sudo sed -i 's/\(net.ipv6.conf.all.disable_ipv6\).*/\1=0/' /etc/sysctl.conf
        fi
        ;;
    esac

    # Build the osbuilder with same distro as the host.
    export osbuilder_distro="$distro"

    cd ${kata_tests_repo_dir}
    .ci/setup.sh
  SHELL

  config.vm.define "fedora", autostart: false do |fedora|
    fedora.vm.box = "fedora/32-cloud-base"
    # Fedora is required to reboot so that the change to cgroups v1
    # makes effect.
    fedora.vm.provision "shell", reboot: true, inline: <<-SHELL
      echo "Need to reboot the VM"
    SHELL
  end

  config.vm.define "ubuntu", autostart: false do |ubuntu|
    ubuntu.vm.box = "generic/ubuntu2004"
  end
end
