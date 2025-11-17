#!/bin/bash

set -e

name="$1"

NAMESPACE="${NAMESPACE:-appcat-e2e}"

echo "=== Starting PostgreSQL CNPG restore test ==="
echo "Namespace: $NAMESPACE"
echo "Source instance: $name"

# Decode and setup kubeconfigs
echo "$CONTROL_PLANE_KUBECONFIG_CONTENT" | base64 -d > /tmp/control-plane-config
echo "$SERVICE_CLUSTER_KUBECONFIG_CONTENT" | base64 -d > /tmp/service-cluster-config

export KUBECONFIG=/tmp/control-plane-config
echo "Using control plane kubeconfig"

# Get the most recent backup
echo "Finding the most recent backup..."
instancens=$(kubectl -n "$NAMESPACE" get vshnpostgresql "$name" -oyaml | yq -r '.status.instanceNamespace')

export KUBECONFIG=/tmp/service-cluster-config

# Detect if running in OpenShift
KUBECTL_ARGS=""
if kubectl api-resources | grep -q "openshift.io"; then
    echo "OpenShift detected, using --as=cluster-admin"
    KUBECTL_ARGS="--as=cluster-admin"
fi

# Get the latest completed backup
backup_name=$(kubectl ${KUBECTL_ARGS} -n "$instancens" get backups.postgresql.cnpg.io -o json | \
    jq -r '.items | map(select(.status.phase == "completed")) | sort_by(.status.stoppedAt) | last | .metadata.name')

if [ -z "$backup_name" ] || [ "$backup_name" == "null" ]; then
    echo "✗ No completed backup found"
    kubectl ${KUBECTL_ARGS} -n "$instancens" get backups.postgresql.cnpg.io
    exit 1
fi

echo "Found backup: $backup_name"

# Get backup details for restore
backup_id=$(kubectl ${KUBECTL_ARGS} -n "$instancens" get backup "$backup_name" -o jsonpath='{.status.backupId}')
backup_server_name=$(kubectl ${KUBECTL_ARGS} -n "$instancens" get backup "$backup_name" -o jsonpath='{.status.serverName}')

echo "  Backup ID: $backup_id"
echo "  Server Name: $backup_server_name"

# Switch back to control plane for creating the restore instance
export KUBECONFIG=/tmp/control-plane-config

echo "Creating new instance with restore from backup..."

# Detect if running in OpenShift
KUBECTL_ARGS=""
if kubectl api-resources | grep -q "openshift.io"; then
    echo "OpenShift detected, using --as=cluster-admin"
    KUBECTL_ARGS="--as=cluster-admin"
fi

# Note: The restore instance was pre-created in 00-install.yaml
# We need to update it with restore configuration
# For CNPG, restore is typically done via the bootstrap section of the cluster spec
# This is handled by the composition function when restore parameters are specified

# Update the restore instance with backup information
kubectl ${KUBECTL_ARGS} apply -f - <<EOF
apiVersion: vshn.appcat.vshn.io/v1
kind: VSHNPostgreSQL
metadata:
  name: ${name}-restore
  namespace: ${NAMESPACE}
  labels:
    appcat.vshn.io/provider-config: kind
spec:
  compositionRef:
    name: vshnpostgrescnpg.vshn.appcat.vshn.io
  parameters:
    restore:
      backupName: ${backup_name}
      claimName: ${name}
    backup:
      schedule: '0 22 * * *'
    security:
      deletionProtection: false
    service:
      majorVersion: "15"
    size:
      plan: standard-2
  writeConnectionSecretToRef:
    name: ${name}-restore-creds
EOF

if [ $? -eq 0 ]; then
    echo "✓ Restore instance created/updated successfully"
else
    echo "✗ Failed to create/update restore instance"
    exit 1
fi

echo ""
echo "✓ CNPG restore test initiated"
echo "  The restore instance will be validated in subsequent test steps"
echo "=== PostgreSQL CNPG restore test setup completed ==="
