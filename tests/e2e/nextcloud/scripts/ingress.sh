#!/bin/bash

set -e

echo "$CONTROL_PLANE_KUBECONFIG_CONTENT" | base64 -d > /tmp/control-plane-config
echo "$SERVICE_CLUSTER_KUBECONFIG_CONTENT" | base64 -d > /tmp/service-cluster-config

ns=$(kubectl --kubeconfig=/tmp/control-plane-config -n "$NAMESPACE" get vshnnextcloud nextcloud-e2e -oyaml | yq -r '.status.instanceNamespace')

ingress_hosts=($(kubectl --kubeconfig=/tmp/service-cluster-config -n "$ns" get ingress -oyaml | yq -r '.items[].spec.tls[].hosts[]'))

nextcloud_found=false
collabora_found=false

for host in "${ingress_hosts[@]}"; do
    if [[ "$host" == "nextcloud-e2e.example.com" ]]; then
        nextcloud_found=true
    elif [[ "$host" == "collabora-e2e.example.com" ]]; then
        collabora_found=true
    fi
done

echo "Found ingress hosts: ${ingress_hosts[*]}"
echo "Nextcloud host found: $nextcloud_found"
echo "Collabora host found: $collabora_found"

[[ "$nextcloud_found" == "true" && "$collabora_found" == "true" ]] || exit 1
