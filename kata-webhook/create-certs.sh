#! /bin/bash
# Copyright (c) 2019 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

WEBHOOK_NS=${1:-"default"}
WEBHOOK_NAME=${2:-"pod-annotate"}
WEBHOOK_SVC="${WEBHOOK_NAME}-webhook"

if ! command -v openssl &>/dev/null; then
	echo "ERROR: command 'openssl' not found."
	exit 1
elif ! command -v kubectl &>/dev/null; then
	echo "ERROR: command 'kubectl' not found."
	exit 1
fi

cleanup() {
	rm -f ./webhookCA*
	rm -f ./webhook.crt
}

trap cleanup EXIT

# Create certs for our webhook
touch $HOME/.rnd
openssl genrsa -out webhookCA.key 2048
openssl req -new -key ./webhookCA.key -subj "/CN=${WEBHOOK_SVC}.${WEBHOOK_NS}.svc" -out ./webhookCA.csr 
openssl x509 -req -days 365 -in webhookCA.csr -signkey webhookCA.key -out webhook.crt

# Create certs secrets for k8s
kubectl create secret generic \
    ${WEBHOOK_SVC}-certs \
    --from-file=key.pem=./webhookCA.key \
    --from-file=cert.pem=./webhook.crt \
    --dry-run=client -o yaml > ./deploy/webhook-certs.yaml

# Set the CABundle on the webhook registration
CA_BUNDLE=$(cat ./webhook.crt | base64 -w0)
sed "s/CA_BUNDLE/${CA_BUNDLE}/" ./deploy/webhook-registration.yaml.tpl > ./deploy/webhook-registration.yaml

