#!/bin/bash

set -exf

ns=$(kubectl -n "$NAMESPACE" get vshnforgejo forgejo-e2e -oyaml | yq -r '.status.instanceNamespace')

fqdn=$(kubectl -n "$ns" get ingress -oyaml | yq -r '.items.[0].spec.tls.[0].hosts[0]')

echo "$fqdn = somesuperingressname.apps.lab-cloudscale-rma-0.appuio.cloud"
[[ "$fqdn" == "somesuperingressname.apps.lab-cloudscale-rma-0.appuio.cloud" ]]
