#!/bin/bash

set -e

NAMESPACE="${NAMESPACE:-appcat-e2e}"

echo "=== Starting PostgreSQL CNPG backup test ==="
echo "Namespace: $NAMESPACE"

# Decode and setup kubeconfigs
echo "$CONTROL_PLANE_KUBECONFIG_CONTENT" | base64 -d > /tmp/control-plane-config
echo "$SERVICE_CLUSTER_KUBECONFIG_CONTENT" | base64 -d > /tmp/service-cluster-config

export KUBECONFIG=/tmp/control-plane-config
echo "Using control plane kubeconfig for instance operations"

echo "Getting instance namespace and cluster name..."
instancens=$(kubectl -n "$NAMESPACE" get vshnpostgresql pg-cnpg-e2e -oyaml | yq -r '.status.instanceNamespace')
comp=$(kubectl -n "$NAMESPACE" get vshnpostgresql pg-cnpg-e2e -oyaml | yq -r '.spec.resourceRef.name')

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

# Verify scheduled backups are configured
echo "Checking for scheduled backups..."
scheduled_backups=$(kubectl ${KUBECTL_ARGS} -n "$instancens" get scheduledbackups.postgresql.cnpg.io -o json 2>/dev/null | jq -r '.items | length')
if [ "$scheduled_backups" -eq 0 ]; then
    echo "⚠ No scheduled backups found, but continuing with on-demand backup test"
else
    echo "✓ Found $scheduled_backups scheduled backup(s)"
fi

# Create an on-demand backup using CNPG Backup CRD
backup_name="e2e-backup-$(date +%s)"
echo "Creating CNPG Backup: $backup_name..."

cat <<EOF | kubectl ${KUBECTL_ARGS} apply -f -
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: $backup_name
  namespace: $instancens
spec:
  cluster:
    name: ${comp}-cluster
  method: barmanObjectStore
EOF

if [ $? -ne 0 ]; then
    echo "✗ Failed to create backup"
    exit 1
fi

echo "Backup resource created, waiting for completion..."

# Wait for backup to complete
timeout=600
elapsed=0
while true; do
    if [ $elapsed -ge $timeout ]; then
        echo "✗ Timeout waiting for backup to complete"
        kubectl ${KUBECTL_ARGS} -n "$instancens" get backup "$backup_name" -o yaml
        exit 1
    fi

    backup_phase=$(kubectl ${KUBECTL_ARGS} -n "$instancens" get backup "$backup_name" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")

    if [ -z "$backup_phase" ]; then
        echo "Waiting for backup status... (${elapsed}s elapsed)"
    elif [ "$backup_phase" == "completed" ]; then
        echo "✓ Backup completed successfully"
        break
    elif [ "$backup_phase" == "failed" ]; then
        echo "✗ Backup failed"
        kubectl ${KUBECTL_ARGS} -n "$instancens" get backup "$backup_name" -o yaml
        exit 1
    else
        echo "Backup status: $backup_phase (${elapsed}s elapsed)"
    fi

    sleep 10
    elapsed=$((elapsed + 10))
done

# Switch back to control plane kubeconfig for checking backup via API
export KUBECONFIG=/tmp/control-plane-config
echo "Using control plane kubeconfig for backup API check"

# Verify backup is visible via the AppCat API
echo "Checking backup visibility via AppCat API..."
timeout=60
elapsed=0
while true; do
    if [ $elapsed -ge $timeout ]; then
        echo "⚠ Warning: Backup not visible via AppCat API after ${timeout}s, but backup completed successfully"
        break
    fi

    api_backup_count=$(kubectl -n "$NAMESPACE" get vshnpostgresbackups.api.appcat.vshn.io 2>/dev/null | grep -c "$backup_name" || echo "0")

    if [ "$api_backup_count" -gt 0 ]; then
        echo "✓ Backup is visible via AppCat API"
        backup_status=$(kubectl -n "$NAMESPACE" get vshnpostgresbackups.api.appcat.vshn.io "$backup_name" -o json 2>/dev/null | jq -r '.status.process.status' || echo "")
        echo "  Backup API status: $backup_status"
        break
    else
        echo "Waiting for backup to appear in AppCat API... (${elapsed}s elapsed)"
    fi

    sleep 5
    elapsed=$((elapsed + 5))
done

# Display backup details
echo ""
echo "=== Backup Details ==="
kubectl ${KUBECTL_ARGS} --kubeconfig=/tmp/service-cluster-config -n "$instancens" get backup "$backup_name" -o yaml | grep -A 20 "status:"

echo ""
echo "✓ CNPG backup test completed successfully"
echo "=== PostgreSQL CNPG backup test completed ==="
