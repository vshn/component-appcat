#!/bin/bash

set -e

name="$1"

backup=$(kubectl -n "$NAMESPACE" get vshnkeycloakbackups.api.appcat.vshn.io -o json | jq -r '.items[0] | .metadata.name')

echo "Create new instance"

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
