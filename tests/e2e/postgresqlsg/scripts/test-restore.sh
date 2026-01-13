#!/bin/bash

set -e

name="$1"

backup=$(kubectl -n "$NAMESPACE" get vshnpostgresbackups.api.appcat.vshn.io -o json | jq -r '.items[0] | .metadata.name')

echo "Create new instance"

# Detect if running in OpenShift
KUBECTL_ARGS=""
if kubectl api-resources | grep -q "openshift.io"; then
    echo "OpenShift detected, using --as=cluster-admin"
    KUBECTL_ARGS="--as=cluster-admin"
fi

kubectl apply ${KUBECTL_ARGS} -f - <<EOF
apiVersion: vshn.appcat.vshn.io/v1
kind: VSHNPostgreSQL
metadata:
  labels:
    appcat.vshn.io/provider-config: kind
  name: ${name}-restore
  namespace: ${NAMESPACE}
spec:
  parameters:
    restore:
      backupName: ${backup}
      claimName: ${name}
    backup:
      schedule: '0 22 * * *'
    security:
      deletionProtection: false
    size:
      plan: standard-2
  writeConnectionSecretToRef:
    name: ${name}-restore-creds
EOF
