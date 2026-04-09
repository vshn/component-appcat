#!/bin/bash

set -e

name="$1"

echo "Creating restore instance ${name}-restore from ${name}"

kubectl apply -f - <<EOF
apiVersion: vshn.appcat.vshn.io/v1
kind: VSHNPostgreSQL
metadata:
  name: ${name}-restore
  namespace: ${NAMESPACE}
spec:
  compositionRef:
    name: vshnpostgrescnpg.vshn.appcat.vshn.io
  parameters:
    restore:
      claimName: ${name}
    backup:
      schedule: '0 22 * * *'
    security:
      deletionProtection: false
    size:
      plan: standard-2
  writeConnectionSecretToRef:
    name: ${name}-restore-creds
EOF

echo "Restore instance ${name}-restore created"
