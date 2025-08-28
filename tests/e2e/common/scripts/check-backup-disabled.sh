#!/bin/bash

set -e

# Get service type and instance name from parameters
SERVICE_TYPE=${1:-}
INSTANCE_NAME=${2:-}

if [ -z "$SERVICE_TYPE" ] || [ -z "$INSTANCE_NAME" ]; then
    echo "Usage: $0 <service_type> <instance_name>"
    echo "Example: $0 vshnredis redis-backup-disabled-test"
    exit 1
fi

# Get instance namespace
instancens=$(kubectl -n "$NAMESPACE" get "$SERVICE_TYPE" "$INSTANCE_NAME" -o yaml | yq -r '.status.instanceNamespace')

# Check that no backup schedules are created
schedules=$(kubectl -n "$instancens" get schedules -o json 2>/dev/null | jq -r '.items | length' || echo "0")

if [ "$schedules" -ne 0 ]; then
    echo "ERROR: Backup schedules were created when backups were disabled"
    kubectl -n "$instancens" get schedules
    exit 1
fi

# Check that no backup bucket was created
buckets=$(kubectl -n "$instancens" get objectbuckets -o json 2>/dev/null | jq -r '.items | length' || echo "0")

if [ "$buckets" -ne 0 ]; then
    echo "ERROR: Backup bucket was created when backups were disabled"
    kubectl -n "$instancens" get objectbuckets
    exit 1
fi

# Check that no backup repository password secret was created
repo_secrets=$(kubectl -n "$instancens" get secrets -l "name.appcat.io/backup-password=backup-repo" -o json 2>/dev/null | jq -r '.items | length' || echo "0")

if [ "$repo_secrets" -ne 0 ]; then
    echo "ERROR: Backup repository password secret was created when backups were disabled"
    kubectl -n "$instancens" get secrets -l "name.appcat.io/backup-password=backup-repo"
    exit 1
fi

# Special handling for services with embedded PostgreSQL
if [[ "$SERVICE_TYPE" == "vshnkeycloak" || "$SERVICE_TYPE" == "vshnnextcloud" ]]; then
    # Check that embedded PostgreSQL also has no backup configuration
    pg_comp=$(kubectl -n "$instancens" get sgclusters.stackgres.io -o json 2>/dev/null | jq -r '.items[0].metadata.name // empty' || echo "")
    
    if [ -n "$pg_comp" ]; then
        backup_config=$(kubectl -n "$instancens" get sgclusters.stackgres.io "$pg_comp" -o json 2>/dev/null | jq -r '.spec.configurations.backups // null')
        
        if [ "$backup_config" != "null" ]; then
            echo "ERROR: Embedded PostgreSQL has backup configuration when backups were disabled"
            kubectl -n "$instancens" get sgclusters.stackgres.io "$pg_comp" -o yaml | yq '.spec.configurations.backups'
            exit 1
        fi
    fi
fi

echo "SUCCESS: No backup resources found when backups are disabled"