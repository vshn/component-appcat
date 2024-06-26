#!/bin/bash

set -e

ns=$(kubectl -n "$NAMESPACE" get vshnnextcloud nextcloud-e2e -oyaml | yq -r '.status.instanceNamespace')

fqdn=$(kubectl -n "$ns" get ingress -oyaml | yq -r '.items.[0].spec.tls.[0].hosts[0]')

echo "$fqdn = nextcloud-e2e.example.com"
[[ "$fqdn" == "nextcloud-e2e.example.com" ]]
