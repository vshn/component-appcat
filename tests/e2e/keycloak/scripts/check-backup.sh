#!/bin/bash

set -e

for ((i = 0 ; i < 10 ; i++ ));
do
    echo "Waiting for backup to be created"
    backup=$(kubectl -n "$NAMESPACE" get vshnkeycloakbackups.api.appcat.vshn.io -o json | jq -r '.items[] | .metadata.name' | tail -n 1)
    if [ "$backup" != "" ]; then
        break
    fi
    sleep 10
done

echo "checking backup status"

backup_status=$(kubectl -n "$NAMESPACE" get vshnkeycloakbackups.api.appcat.vshn.io "$backup" -o json | jq -r '.status.databaseBackupStatus.process.status')

while [ "$backup_status" == "Running" ]; do
    backup_status=$(kubectl -n "$NAMESPACE" get vshnkeycloakbackups.api.appcat.vshn.io "$backup" -o json | jq -r '.status.databaseBackupStatus.process.status')
done

if [ "$backup_status" != "Completed" ]; then
    echo "Backup failed"
    exit 1
fi

echo "Backup succeeded"
