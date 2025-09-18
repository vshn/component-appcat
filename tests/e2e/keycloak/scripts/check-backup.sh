#!/bin/bash

set -e

comp=$(kubectl -n "$NAMESPACE" get vshnkeycloak keycloak-e2e -oyaml | yq -r '.spec.resourceRef.name')
instancens=vshn-postgresql-$comp-pg

cat <<EOF | kubectl apply -f -
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

echo "checking backup status"

backup_status=$(kubectl -n "$NAMESPACE" get vshnkeycloakbackups.api.appcat.vshn.io e2e-backup -o json | jq -r '.status.databaseBackupStatus.process.status')

while [ "$backup_status" == "Running" ] || [ "$backup_status" == "Pending" ] || [ "$backup_status" == "null" ]; do
    backup_status=$(kubectl -n "$NAMESPACE" get vshnkeycloakbackups.api.appcat.vshn.io e2e-backup -o json | jq -r '.status.databaseBackupStatus.process.status')
    sleep 1
done

if [ "$backup_status" != "Completed" ]; then
    echo "Backup failed"
    exit 1
fi

echo "Backup succeeded"
