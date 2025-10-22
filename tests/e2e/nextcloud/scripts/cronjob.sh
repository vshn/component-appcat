#!/bin/bash

set -e

echo "$CONTROL_PLANE_KUBECONFIG_CONTENT" | base64 -d > /tmp/control-plane-config
echo "$SERVICE_CLUSTER_KUBECONFIG_CONTENT" | base64 -d > /tmp/service-cluster-config

ns=$(kubectl --kubeconfig=/tmp/control-plane-config  -n "$NAMESPACE" get vshnnextcloud nextcloud-e2e -oyaml | yq -r '.status.instanceNamespace')

instance=${ns#*vshn-nextcloud-}

cronjob_found=$(kubectl --kubeconfig=/tmp/service-cluster-config  -n "$ns" get cronjob "${instance}-cron" -o jsonpath='{.metadata.name}')

if [ "$cronjob_found" == "${instance}-cron" ]; then
    echo "Cronjob found: ${cronjob_found}"
    exit
else
    echo "Cronjob not found"
    exit 1
fi



exit 1
