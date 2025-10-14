#!/bin/bash

set -e

NAMESPACE="${NAMESPACE:-appcat-e2e}"

echo "=== Starting Keycloak backup test ==="
echo "Namespace: $NAMESPACE"

# Decode and setup kubeconfigs
echo "$CONTROL_PLANE_KUBECONFIG_CONTENT" | base64 -d > /tmp/control-plane-config
echo "$SERVICE_CLUSTER_KUBECONFIG_CONTENT" | base64 -d > /tmp/service-cluster-config

# Use control plane kubeconfig to get composite name
export KUBECONFIG=/tmp/control-plane-config
echo "Using control plane kubeconfig for instance operations"

echo "Getting composite name..."
comp=$(kubectl -n "$NAMESPACE" get vshnkeycloak keycloak-e2e -o jsonpath='{.spec.resourceRef.name}')

if [ -z "$comp" ]; then
  echo "✗ ERROR: Could not retrieve composite name"
  exit 1
fi

echo "Composite name: $comp"

instancens="vshn-postgresql-$comp-pg"
echo "Instance namespace: $instancens"

# Switch to service cluster kubeconfig to create SGBackup
export KUBECONFIG=/tmp/service-cluster-config
echo "Using service cluster kubeconfig for SGBackup creation"

# Detect if running in OpenShift
KUBECTL_ARGS=""
if kubectl api-resources | grep -q "openshift.io"; then
    echo "OpenShift detected, using --as=cluster-admin"
    KUBECTL_ARGS="--as=cluster-admin"
fi

echo "Creating SGBackup..."
cat <<EOF | kubectl apply ${KUBECTL_ARGS} -f -
apiVersion: stackgres.io/v1
kind: SGBackup
metadata:
  name: e2e-backup
  namespace: $instancens
spec:
  managedLifecycle: true
  reconciliationTimeout: 300
  sgCluster: $comp-pg
EOF

# Switch back to control plane kubeconfig to check backup status
export KUBECONFIG=/tmp/control-plane-config
echo "Using control plane kubeconfig for backup status check"

echo "Checking backup status..."

backup_status=$(kubectl ${KUBECTL_ARGS} -n "$NAMESPACE" get vshnkeycloakbackups.api.appcat.vshn.io e2e-backup -o json | jq -r '.status.databaseBackupStatus.process.status')

while [ "$backup_status" == "Running" ] || [ "$backup_status" == "Pending" ] || [ "$backup_status" == "null" ]; do
    echo "Backup status: $backup_status"
    backup_status=$(kubectl ${KUBECTL_ARGS} -n "$NAMESPACE" get vshnkeycloakbackups.api.appcat.vshn.io e2e-backup -o json | jq -r '.status.databaseBackupStatus.process.status')
    sleep 1
done

if [ "$backup_status" != "Completed" ]; then
    echo "✗ Backup failed with status: $backup_status"
    exit 1
fi

echo "✓ Backup succeeded"
echo "=== Keycloak backup test completed successfully ==="
