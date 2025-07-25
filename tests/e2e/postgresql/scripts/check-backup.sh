#!/bin/bash

set -e

instancens=$(kubectl -n "$NAMESPACE" get vshnpostgresql postgresql-e2e-test -oyaml | yq -r '.status.instanceNamespace')
comp=$(kubectl -n "$NAMESPACE" get vshnpostgresql postgresql-e2e-test -oyaml | yq -r '.spec.resourceRef.name')

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

echo "checking backup status"

backup_status=$(kubectl -n "$NAMESPACE" get vshnpostgresbackups.api.appcat.vshn.io e2e-backup -o json | jq -r '.status.process.status')

while [ "$backup_status" == "Running" ] || [ "$backup_status" == "Pending" ]; do
    backup_status=$(kubectl -n "$NAMESPACE" get vshnpostgresbackups.api.appcat.vshn.io e2e-backup -o json | jq -r '.status.process.status')
    sleep 1
done

if [ "$backup_status" != "Completed" ]; then
    echo "Backup failed"
    exit 1
fi

echo "Backup succeeded"
