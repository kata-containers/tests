#!/bin/bash
#
# Copyright (c) 2023 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

cidir=$(dirname "$0")
source "${cidir}/lib.sh"

main() {
info "Install Kata + SGX components"
pushd "${GOPATH}/src/${test_repo}/integration/kubernetes"
sudo -E ./init.sh
sudo -E kubectl apply -f https://raw.githubusercontent.com/kata-containers/kata-containers/main/tools/packaging/kata-deploy/kata-rbac/base/kata-rbac.yaml
sudo -E kubectl apply -f https://raw.githubusercontent.com/kata-containers/kata-containers/main/tools/packaging/kata-deploy/kata-deploy/base/kata-deploy-stable.yaml
sudo -E kubectl -n kube-system wait --timeout=10m --for=condition=Ready -l name=kata-deploy pod
sudo -E kubectl apply -f https://raw.githubusercontent.com/kata-containers/kata-containers/main/tools/packaging/kata-deploy/runtimeclasses/kata-runtimeClasses.yaml
sudo rm /opt/kata/share/defaults/kata-containers/configuration.toml
sudo cp /opt/kata/share/defaults/kata-containers/configuration-clh.toml /opt/kata/share/defaults/kata-containers/configuration.toml
sudo systemctl daemon-reload
sudo -E ./cleanup_env.sh
popd
}
