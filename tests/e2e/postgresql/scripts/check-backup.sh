#!/bin/bash

set -e

NAMESPACE="${NAMESPACE:-appcat-e2e}"

echo "=== Starting PostgreSQL backup test ==="
echo "Namespace: $NAMESPACE"

# Decode and setup kubeconfigs
echo "$CONTROL_PLANE_KUBECONFIG_CONTENT" | base64 -d > /tmp/control-plane-config
echo "$SERVICE_CLUSTER_KUBECONFIG_CONTENT" | base64 -d > /tmp/service-cluster-config

export KUBECONFIG=/tmp/control-plane-config
echo "Using control plane kubeconfig for instance operations"

echo "Getting instance namespace and cluster name..."
instancens=$(kubectl -n "$NAMESPACE" get vshnpostgresql postgresql-e2e-test -oyaml | yq -r '.status.instanceNamespace')
comp=$(kubectl -n "$NAMESPACE" get vshnpostgresql postgresql-e2e-test -oyaml | yq -r '.spec.resourceRef.name')

echo "Instance namespace: $instancens"
echo "Cluster name: $comp"

# Switch to service cluster kubeconfig for creating the backup
export KUBECONFIG=/tmp/service-cluster-config
echo "Using service cluster kubeconfig for backup operations"

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
  sgCluster: $comp
EOF

# Switch back to control plane kubeconfig for checking backup status
export KUBECONFIG=/tmp/control-plane-config
echo "Using control plane kubeconfig for backup status check"

echo "Checking backup status..."

backup_status=$(kubectl -n "$NAMESPACE" get vshnpostgresbackups.api.appcat.vshn.io e2e-backup -o json | jq -r '.status.process.status')

while [ "$backup_status" == "Running" ] || [ "$backup_status" == "Pending" ] || [ "$backup_status" == "null" ]; do
    echo "Backup status: $backup_status"
    backup_status=$(kubectl -n "$NAMESPACE" get vshnpostgresbackups.api.appcat.vshn.io e2e-backup -o json | jq -r '.status.process.status')
    sleep 1
done

if [ "$backup_status" != "Completed" ]; then
    echo "✗ Backup failed with status: $backup_status"
    exit 1
fi

echo "✓ Backup succeeded"
echo "=== PostgreSQL backup test completed successfully ==="
