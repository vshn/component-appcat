#!/bin/bash

set -e

NAMESPACE="${NAMESPACE:-appcat-e2e}"

echo "=== Starting PostgreSQL backup test ==="
echo "Namespace: $NAMESPACE"

echo "Getting instance namespace and cluster name..."
instancens=$(kubectl -n "$NAMESPACE" get vshnpostgresql pg-sg-e2e -oyaml | yq -r '.status.instanceNamespace')
comp=$(kubectl -n "$NAMESPACE" get vshnpostgresql pg-sg-e2e -oyaml | yq -r '.spec.resourceRef.name')

echo "Instance namespace: $instancens"
echo "Cluster name: $comp"

echo "Creating SGBackup..."
cat <<EOF | kubectl apply -f -
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
