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

# Get the backup name
echo "Getting backup name..."
backup=$(kubectl -n "$NAMESPACE" get vshnkeycloakbackups.api.appcat.vshn.io -o json | jq -r '.items[0] | .metadata.name')

if [ -z "$backup" ] || [ "$backup" == "null" ]; then
  echo "✗ ERROR: No backup found in namespace $NAMESPACE"
  exit 1
fi

echo "Backup name: $backup"

# Create new instance with restore
echo "Creating new Keycloak instance from backup..."

kubectl apply -f - <<EOF
apiVersion: vshn.appcat.vshn.io/v1
kind: VSHNKeycloak
metadata:
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
