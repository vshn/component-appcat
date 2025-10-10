#!/bin/bash

set -e

name="$1"
NAMESPACE="${NAMESPACE:-appcat-e2e}"

if [ -z "$name" ]; then
  echo "Usage: $0 <instance_name>"
  exit 1
fi

echo "=== Starting Keycloak restore test ==="
echo "Instance name: $name"
echo "Namespace: $NAMESPACE"

# Decode and setup kubeconfigs
echo "$CONTROL_PLANE_KUBECONFIG_CONTENT" | base64 -d > /tmp/control-plane-config
echo "$SERVICE_CLUSTER_KUBECONFIG_CONTENT" | base64 -d > /tmp/service-cluster-config

# Use control plane kubeconfig for all operations
export KUBECONFIG=/tmp/control-plane-config
echo "Using control plane kubeconfig for restore operations"

KUBECTL_ARGS=""
if kubectl api-resources | grep -q "openshift.io"; then
    echo "OpenShift detected, using --as=cluster-admin"
    KUBECTL_ARGS="--as=cluster-admin"
fi

# Get the backup name
echo "Getting backup name..."
backup=$(kubectl ${KUBECTL_ARGS} -n "$NAMESPACE" get vshnkeycloakbackups.api.appcat.vshn.io -o json | jq -r '.items[0] | .metadata.name')

if [ -z "$backup" ] || [ "$backup" == "null" ]; then
  echo "✗ ERROR: No backup found in namespace $NAMESPACE"
  exit 1
fi

echo "Backup name: $backup"

# Create new instance with restore
echo "Creating new Keycloak instance from backup..."

kubectl apply ${KUBECTL_ARGS} -f - <<EOF
apiVersion: vshn.appcat.vshn.io/v1
kind: VSHNKeycloak
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
    service:
      version: "26"
      fqdn: keycloak-e2e-restore.example.com
    size:
      plan: standard-2
  writeConnectionSecretToRef:
    name: keycloak-e2e-restore
EOF

echo "✓ Keycloak restore instance created successfully"
echo "=== Keycloak restore test completed successfully ==="
