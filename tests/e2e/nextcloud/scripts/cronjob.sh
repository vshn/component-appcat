#!/bin/bash

set -e

ns=$(kubectl -n "$NAMESPACE" get vshnnextcloud nextcloud-e2e -oyaml | yq -r '.status.instanceNamespace')

instance=${ns#*vshn-nextcloud-}

cronjob_found=$(kubectl -n "$ns" get cronjob "${instance}-cron" -o jsonpath='{.metadata.name}')

if [ "$cronjob_found" == "${instance}-cron" ]; then
    echo "Cronjob found: ${cronjob_found}"
    exit
else
    echo "Cronjob not found"
    exit 1
fi



exit 1
