#!/bin/bash
#
# Copyright (c) 2017-2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail

cidir=$(dirname "$0")
source "${cidir}/lib.sh"
source /etc/os-release || source /usr/lib/os-release

echo "Install go-md2man"
go_md2man_url=$(get_test_version "externals.go-md2man.url")
go_md2man_version=$(get_test_version "externals.go-md2man.version")
go_md2man_repo=${go_md2man_url/https:\/\/}
go install "${go_md2man_repo}"@"${go_md2man_version}"

echo "Install conmon"
conmon_url=$(get_version "externals.conmon.url")
conmon_version=$(get_version "externals.conmon.version")
conmon_repo=${conmon_url/https:\/\/}
mkdir -p "$GOPATH/src/${conmon_repo}"
git clone "https://${conmon_repo}.git" "$GOPATH/src/${conmon_repo}" || true
pushd "$GOPATH/src/${conmon_repo}"
git checkout "${conmon_version}"
make
sudo -E make install
popd

echo "Configure registries"
sudo mkdir -p /etc/containers/registries.conf.d/
cat <<EOF| sudo tee "/etc/containers/registries.conf.d/ciregistries.conf"
unqualified-search-registries = ["registry.fedoraproject.org", "registry.access.redhat.com", "registry.centos.org", "docker.io"]

[aliases]
  # centos
  "centos" = "quay.io/centos/centos"
  # containers
  "skopeo" = "quay.io/skopeo/stable"
  "buildah" = "quay.io/buildah/stable"
  "podman" = "quay.io/podman/stable"
  # docker
  "alpine" = "docker.io/library/alpine"
  "docker" = "docker.io/library/docker"
  "registry" = "docker.io/library/registry"
  "hello-world" = "docker.io/library/hello-world"
  "swarm" = "docker.io/library/swarm"
  # Fedora
  "fedora-minimal" = "registry.fedoraproject.org/fedora-minimal"
  "fedora" = "registry.fedoraproject.org/fedora"
  # openSUSE
  "opensuse/tumbleweed" = "registry.opensuse.org/opensuse/tumbleweed"
  "opensuse/tumbleweed-dnf" = "registry.opensuse.org/opensuse/tumbleweed-dnf"
  "opensuse/tumbleweed-microdnf" = "registry.opensuse.org/opensuse/tumbleweed-microdnf"
  "opensuse/leap" = "registry.opensuse.org/opensuse/leap"
  "opensuse/busybox" = "registry.opensuse.org/opensuse/busybox"
  "tumbleweed" = "registry.opensuse.org/opensuse/tumbleweed"
  "tumbleweed-dnf" = "registry.opensuse.org/opensuse/tumbleweed-dnf"
  "tumbleweed-microdnf" = "registry.opensuse.org/opensuse/tumbleweed-microdnf"
  "leap" = "registry.opensuse.org/opensuse/leap"
  "tw-busybox" = "registry.opensuse.org/opensuse/busybox"
  # SUSE
  "suse/sle15" = "registry.suse.com/suse/sle15"
  "suse/sles12sp5" = "registry.suse.com/suse/sles12sp5"
  "suse/sles12sp4" = "registry.suse.com/suse/sles12sp4"
  "suse/sles12sp3" = "registry.suse.com/suse/sles12sp3"
  "sle15" = "registry.suse.com/suse/sle15"
  "sles12sp5" = "registry.suse.com/suse/sles12sp5"
  "sles12sp4" = "registry.suse.com/suse/sles12sp4"
  "sles12sp3" = "registry.suse.com/suse/sles12sp3"
  # Red Hat Enterprise Linux
  "rhel" = "registry.access.redhat.com/rhel"
  "rhel6" = "registry.access.redhat.com/rhel6"
  "rhel7" = "registry.access.redhat.com/rhel7"
  "ubi7" = "registry.access.redhat.com/ubi7"
  "ubi7-init" = "registry.access.redhat.com/ubi7-init"
  "ubi7-minimal" = "registry.access.redhat.com/ubi7-minimal"
  "ubi8" = "registry.access.redhat.com/ubi8"
  "ubi8-minimal" = "registry.access.redhat.com/ubi8-minimal"
  "ubi8-init" = "registry.access.redhat.com/ubi8-init"
  "ubi8-micro" = "registry.access.redhat.com/ubi8-micro"
  "ubi8/ubi" = "registry.access.redhat.com/ubi8/ubi"
  "ubi8/ubi-minimal" = "registry.access.redhat.com/ubi8-minimal"
  "ubi8/ubi-init" = "registry.access.redhat.com/ubi8-init"
  "ubi8/ubi-micro" = "registry.access.redhat.com/ubi8-micro"
  # Debian
  "debian" = "docker.io/library/debian"
  # Oracle Linux
  "oraclelinux" = "container-registry.oracle.com/os/oraclelinux"

# As done for containerd, we need to ensure we add support for the local
# registry for CRI-O as well.
# We mark it as "insecure" as we're not setting it up using TLS.
[[registry]]
location="localhost:5000"
insecure=true
EOF

echo "Get CRI-O sources"
kubernetes_sigs_org="github.com/kubernetes-sigs"
ghprbGhRepository="${ghprbGhRepository:-}"
crio_repo=$(get_version "externals.crio.url")
crio_repo_git="${crio_repo}.git"
# remove https:// from the url
crio_repo="${crio_repo#*//}"

crio_branch=$(get_version "externals.crio.branch")
crictl_repo=$(get_version "externals.critools.url")
crictl_version=$(get_version "externals.critools.version")
crictl_tag_prefix="v"

mkdir -p "${GOPATH}/src/${crio_repo}"
git clone "$crio_repo_git" "${GOPATH}/src/${crio_repo}" || true

if [ "$ghprbGhRepository" != "${crio_repo/github.com\/}" ]
then
	# Only fetch and checkout if we are not testing changes in the cri-o repo. 
	pushd "${GOPATH}/src/${crio_repo}"
	git fetch
	git checkout "${crio_branch}"
	popd
fi

pushd "${GOPATH}/src/${crio_repo}"
echo "Installing CRI-O"
make clean
make BUILDTAGS='seccomp selinux exclude_graphdriver_btrfs exclude_graphdriver_devicemapper libdm_no_deferred_remove'
make test-binaries
sudo -E PATH=$PATH sh -c "make install"
sudo -E PATH=$PATH sh -c 'crio -d "" --log-level "debug" --cgroup-manager "systemd" --storage-driver "overlay" --storage-opt "overlay.override_kernel_check=1" config > crio.conf'
sudo -E PATH=$PATH sh -c "make install.config"

containers_config_path="/etc/containers"
echo "Copy containers policy from CRI-O repo to $containers_config_path"
sudo mkdir -p "$containers_config_path"
sudo install -m0444 test/policy.json "$containers_config_path"
popd

# Install cri-tools
echo "Installing CRI Tools"
crictl_url="${crictl_repo}/releases/download/v${crictl_version}/crictl-${crictl_tag_prefix}${crictl_version}-linux-$(${cidir}/kata-arch.sh -g).tar.gz"
curl -Ls "$crictl_url" | sudo tar xfz - -C /usr/local/bin

echo "Install runc for CRI-O"
runc_version=$(get_version "externals.runc.version")
mkdir -p "${GOPATH}/src/github.com/opencontainers/runc"
git clone https://github.com/opencontainers/runc.git "${GOPATH}/src/github.com/opencontainers/runc"
pushd "${GOPATH}/src/github.com/opencontainers/runc"
git checkout "$runc_version"
typeset -a build_union
lib_union=(libapparmor libseccomp libselinux)
for item in ${lib_union[*]}
do
if pkg-config --exists ${item}; then
	build_union+=(${item#lib})
fi
done
make BUILDTAGS="$(IFS=" "; echo "${build_union[*]}")"
sudo -E install -D -m0755 runc "/usr/local/bin/crio-runc"
# Allow other tests to find the binary by it's normal name
sudo ln -s /usr/local/bin/crio-runc /usr/local/bin/runc
popd

service_path="/etc/systemd/system"
kubelet_service_dir="${service_path}/kubelet.service.d/"

sudo mkdir -p "${kubelet_service_dir}"

sudo rm -f "${kubelet_service_dir}/0-containerd.conf"
cat <<EOF| sudo tee "${kubelet_service_dir}/0-crio.conf"
[Service]
Environment="KUBELET_EXTRA_ARGS=--container-runtime=remote --runtime-request-timeout=15m --container-runtime-endpoint=unix:///var/run/crio/crio.sock"
EOF

echo "Reload systemd services"
sudo systemctl daemon-reload
