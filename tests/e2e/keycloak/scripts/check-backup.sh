#!/bin/bash

set -e

NAMESPACE="${NAMESPACE:-appcat-e2e}"

echo "=== Starting Keycloak backup test ==="
echo "Namespace: $NAMESPACE"

echo "Getting composite name..."
comp=$(kubectl -n "$NAMESPACE" get vshnkeycloak keycloak-e2e -o jsonpath='{.spec.resourceRef.name}')

if [ -z "$comp" ]; then
  echo "✗ ERROR: Could not retrieve composite name"
  exit 1
fi

echo "Composite name: $comp"

instancens="vshn-postgresql-$comp-pg"
echo "Instance namespace: $instancens"

echo "Creating CNPG Backup..."
cat <<EOF | kubectl apply -f -
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: e2e-backup
  namespace: $instancens
spec:
  method: plugin
  cluster:
    name: postgresql
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
EOF

echo "Checking backup status..."

backup_status=$(kubectl -n "$NAMESPACE" get vshnkeycloakbackups.api.appcat.vshn.io e2e-backup -o json | jq -r '.status.databaseBackupStatus.process.status')

while [ "$backup_status" == "running" ] || [ "$backup_status" == "pending" ] || [ "$backup_status" == "started" ] || [ "$backup_status" == "null" ]; do
    echo "Backup status: $backup_status"
    backup_status=$(kubectl -n "$NAMESPACE" get vshnkeycloakbackups.api.appcat.vshn.io e2e-backup -o json | jq -r '.status.databaseBackupStatus.process.status')
    sleep 1
done

if [ "$backup_status" != "completed" ]; then
    echo "✗ Backup failed with status: $backup_status"
    exit 1
fi

echo "✓ Backup succeeded"
echo "=== Keycloak backup test completed successfully ==="
