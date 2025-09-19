#!/bin/bash

set -e

# PostgreSQL-specific backup disabled checks
SERVICE_TYPE="vshnpostgresql"
INSTANCE_NAME="postgresql-backup-disabled-test"

instancens=$(kubectl -n "$NAMESPACE" get "$SERVICE_TYPE" "$INSTANCE_NAME" -o yaml | yq -r '.status.instanceNamespace')
comp=$(kubectl -n "$NAMESPACE" get "$SERVICE_TYPE" "$INSTANCE_NAME" -o yaml | yq -r '.spec.resourceRef.name')

# Check that SGCluster has no backup configuration (PostgreSQL-specific)
backup_config=$(kubectl -n "$instancens" get sgclusters.stackgres.io "$comp" -o json 2>/dev/null | jq -r '.spec.configurations.backups // null')

if [ "$backup_config" != "null" ]; then
    echo "ERROR: SGCluster has backup configuration when backups were disabled"
    kubectl -n "$instancens" get sgclusters.stackgres.io "$comp" -o yaml | yq '.spec.configurations.backups'
    exit 1
fi

# Use common backup-disabled check script for the rest
exec "$(dirname "$0")/check-backup-disabled.sh" "$SERVICE_TYPE" "$INSTANCE_NAME"