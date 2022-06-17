export WORKING_DIR="/root"
export GOROOT="/usr/local/go"
export GOPATH="${WORKING_DIR}/go"
export PATH="${PATH}:${GOROOT}/bin"
export KERNEL_INSTALL_DIR=/root/kernel-build

checkout_pr_3025()
{
        cd $WORKING_DIR

        # Clone kata-containers repo and checkout PR 3025
        git clone https://github.com/kata-containers/kata-containers.git
        cd kata-containers
        gh pr checkout 3025
}

install_kata()
{
        cd $WORKING_DIR/kata-containers

        # Build and install the CC Kata Containers runtime
        export GO111MODULE=on
        cd $WORKING_DIR/kata-containers/src/runtime
        make && sudo -E PATH=$PATH make install
}

build_kata_agent()
{
        cd $WORKING_DIR/kata-containers/src/agent

        sed -i -e 's/mem_controller.set_kmem_limit(1)/info!\(sl!\(\), "Skipping kmem limit setting as not supported in kernel > 5.16"\);\n        \/\/mem_controller.set_kmem_limit(1)/g' ./rustjail/src/cgroups/fs/mod.rs
        sed -i -e 's/mem_controller.set_kmem_limit(-1)/\/\/mem_controller.set_kmem_limit(-1)/g' ./rustjail/src/cgroups/fs/mod.rs

        # Clean and build
        cargo clean
        make
}

build_rootfs()
{
        cd $WORKING_DIR/kata-containers/tools/osbuilder/rootfs-builder

        sed -i -e 's/pushd attestation-agent/pushd attestation-agent\/app/g' rootfs.sh

        script -fec 'sudo -E GOPATH=$GOPATH AGENT_INIT=yes USE_DOCKER=true DOCKER_RUNTIME=runc AA_KBC=offline_sev_kbc SKOPEO_UMOCI=yes ./rootfs.sh ubuntu KERNEL_MODULES_DIR'

tee rootfs-focal/etc/default/agent.cfg <<EOF
aa_kbc_params = "offline_sev_kbc::null"
[endpoints]
allowed = [
"AddARPNeighborsRequest",
"AddSwapRequest",
"CloseStdinRequest",
"CopyFileRequest",
"CreateContainerRequest",
"CreateSandboxRequest",
"DestroySandboxRequest",
"GetMetricsRequest",
"GetOOMEventRequest",
"GuestDetailsRequest",
"ListInterfacesRequest",
"ListRoutesRequest",
"MemHotplugByProbeRequest",
"OnlineCPUMemRequest",
"PauseContainerRequest",
"PullImageRequest",
"ReadStreamRequest",
"RemoveContainerRequest",
"ResumeContainerRequest",
"SetGuestDateTimeRequest",
"SignalProcessRequest",
"StartContainerRequest",
"StartTracingRequest",
"StatsContainerRequest",
"StopTracingRequest",
"TtyWinResizeRequest",
"UpdateContainerRequest",
"UpdateInterfaceRequest",
"UpdateRoutesRequest",
"WaitProcessRequest",
"WriteStreamRequest"
]
EOF

        ROOTFS_DIR="$WORKING_DIR/kata-containers/tools/osbuilder/rootfs-builder/rootfs-focal"
        export ARCH=$(uname -m)
        [ ${ARCH} == "ppc64le" ] || [ ${ARCH} == "s390x" ] && export LIBC=gnu || export LIBC=musl
        [ ${ARCH} == "ppc64le" ] && export ARCH=powerpc64le
        sudo install -o root -g root -m 0550 -T ../../../src/agent/target/${ARCH}-unknown-linux-${LIBC}/release/kata-agent ${ROOTFS_DIR}/sbin/init

}

build_kernel()
{
        cd $WORKING_DIR
        git clone https://github.com/confidential-containers-demo/linux.git
        cd linux
        git checkout conf-comp-secret-v10

        # Copy config file
        cp /root/test/.config ./

        make olddefconfig # save general config

        # config options
        ./scripts/config --enable CONFIG_AMD_MEM_ENCRYPT
        ./scripts/config --enable CONFIG_AMD_MEM_ENCRYPT_ACTIVE_BY_DEFAULT
        ./scripts/config --enable AMD_MEM_ENCRYPT_ACTIVE_BY_DEFAULT
        ./scripts/config --enable CONFIG_CRYPTO_DEV_SP_PSP
        ./scripts/config --enable CONFIG_CRYPTO_DEV_CCP
        ./scripts/config --enable CONFIG_SECURITYFS
        ./scripts/config --enable CONFIG_VIRT_DRIVERS
        ./scripts/config --enable CONFIG_EFI
        ./scripts/config --enable CONFIG_EFI_STUB
        ./scripts/config --module CONFIG_EFI_SECRET
        ./scripts/config --enable CONFIG_MODULE_SIG
        ./scripts/config --enable CONFIG_MODULES

        make kvm_guest.config
        make olddefconfig

        #in .config file change CONFIG_X86_X32 to n
        # build
        KERNEL_INSTALL_DIR=/root/kernel-build
        mkdir -p ${KERNEL_INSTALL_DIR}
        make -j $(($(nproc)-1))
        make INSTALL_PATH=${KERNEL_INSTALL_DIR} install
        make -j16 INSTALL_MOD_STRIP=1 INSTALL_MOD_PATH=${KERNEL_INSTALL_DIR} modules_install

        sudo install -o root -g root -m 0640 -D "${KERNEL_INSTALL_DIR}/vmlinuz-5.17.0-rc6+" "/usr/share/kata-containers/vmlinuz-5.17.0-rc6+"
}

build_initrd()
{
        cd $WORKING_DIR/kata-containers/tools/osbuilder/initrd-builder
        script -fec 'sudo -E AGENT_INIT=yes USE_DOCKER=true DOCKER_RUNTIME=runc AA_KBC=offline_sev_kbc SKOPEO_UMOCI=yes ./initrd_builder.sh /root/kata-containers/tools/osbuilder/rootfs-builder/rootfs-focal'

        # Install the initrd image in the kata-containers directory
        image="kata-containers-sev-initrd.img"
        sudo install -o root -g root -m 0640 -D kata-containers-initrd.img "/usr/share/kata-containers/${image}"
}

start_gop_server()
{
        cd $WORKING_DIR/scripts

        digest=$(python $WORKING_DIR/scripts/calculate_hash.py --ovmf "/root/edk2/Build/AmdSev/DEBUG_GCC5/FV/OVMF.fd" --kernel "/usr/share/kata-containers/vmlinuz-5.17.0-rc6+" --initrd "/usr/share/kata-containers/kata-containers-sev-initrd.img" --cmdline "tsc=reliable no_timer_check rcupdate.rcu_expedited=1 i8042.direct=1 i8042.dumbkbd=1 i8042.nopnp=1 i8042.noaux=1 noreplace-smp reboot=k console=hvc0 console=hvc1 cryptomgr.notests net.ifnames=0 pci=lastbus=0 debug panic=1 nr_cpus=48 scsi_mod.scan=none agent.log=debug agent.log=debug initcall_debug agent.config_file=/etc/default/agent.cfg console=ttyAMA0,115200 console=tty highres=off console=ttyS0" | grep "Firmware Digest" | sed 's/Firmware Digest: //g')

        cd guest-owner-proxy
        jq --arg digest "$digest" '."KEYSET-1"."allowed_digests"[."KEYSET-1"."allowed_digests" | length] |= . + $digest' keysets.json | sponge keysets.json

        ./gop-server.py &
}

run_test()
{
        cd $WORKING_DIR/test

        kubectl create -f $WORKING_DIR/test/ccv0-ssh.yaml

        sleep 5

        pod_name=$(kubectl get pod | grep ccv0 | awk '{print $1;}')

        kubectl logs $pod_name | grep -i sev

}

cleanup()
{
        kubectl delete -f $WORKING_DIR/test/ccv0-ssh.yaml
}

main()
{
        checkout_pr_3025
        build_kata_agent
        build_rootfs
        build_kernel
        build_initrd
		install_kata
        start_gop_server

        run_test

        cleanup
}

main $@
