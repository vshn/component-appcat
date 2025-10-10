#!/bin/bash

set -e

type="$1"
name="$2"
kind="$3"
NAMESPACE="${4:-appcat-e2e}"

if [ -z "$type" ] || [ -z "$name" ] || [ -z "$kind" ]; then
  echo "Usage: $0 <resource_type> <resource_name> <kind> [namespace]"
  echo "Example: $0 vshnpostgresql pgsql-test VSHNPostgreSQL appcat-e2e"
  exit 1
fi

echo "=== Starting provider config validation webhook test ==="
echo "Type: $type"
echo "Name: $name"
echo "Kind: $kind"
echo "Namespace: $NAMESPACE"

# Decode and setup kubeconfigs
echo "$CONTROL_PLANE_KUBECONFIG_CONTENT" | base64 -d > /tmp/control-plane-config
echo "$SERVICE_CLUSTER_KUBECONFIG_CONTENT" | base64 -d > /tmp/service-cluster-config

# Use control plane kubeconfig for all operations
export KUBECONFIG=/tmp/control-plane-config
echo "Using control plane kubeconfig for webhook validation test"

echo "Testing provider config validation webhook for $type ($kind)"

# Try to create instance with invalid provider config - this should fail
echo "Attempting to create instance with invalid provider config..."
if kubectl -n "$NAMESPACE" apply -f - <<EOF 2>/dev/null; then
apiVersion: vshn.appcat.vshn.io/v1
kind: $kind
metadata:
  name: $name
  labels:
    appcat.vshn.io/provider-config: "nonexistent-config"
spec:
  parameters:
    security:
      deletionProtection: false
  writeConnectionSecretToRef:
    name: ${name}-creds-test
EOF
  # If creation succeeded, the webhook failed - this is an error
  echo "✗ ERROR: Instance with invalid provider config was created - webhook validation failed!"
  # Clean up the incorrectly created instance
  kubectl -n "$NAMESPACE" delete "$type" "$name" --ignore-not-found=true || true
  exit 1
else
  # If creation failed, the webhook worked correctly
  echo "SUCCESS: Webhook correctly blocked creation with invalid provider config"
fi

# Verify the instance was not created
echo "Verifying instance was not created..."
if kubectl -n "$NAMESPACE" get "$type" "$name" 2>/dev/null; then
  echo "ERROR: Instance should not exist after webhook validation failure"
  kubectl -n "$NAMESPACE" delete "$type" "$name" --ignore-not-found=true || true
  exit 1
else
  echo "SUCCESS: Instance correctly not created"
fi

echo "=== Provider config validation webhook test completed successfully ==="
