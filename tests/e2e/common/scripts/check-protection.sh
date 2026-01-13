#!/bin/bash
set -e

# Parse arguments
TYPE="$1"
NAME="$2"
NAMESPACE="${3:-appcat-e2e}"

# Cleanup function to ensure the resource has deletion protection disabled if script exits unexpectedly
cleanup() {
  local exit_code=$?
  echo "Running cleanup..."

  if [ -n "$TYPE" ] && [ -n "$NAME" ] && [ -n "$NAMESPACE" ]; then
    echo "Attempting to disable deletion protection..."
    kubectl -n "$NAMESPACE" patch "$TYPE" "$NAME" -p '{"spec":{"parameters":{"security":{"deletionProtection": false}}}}' --type merge 2>/dev/null || true
  fi

  exit $exit_code
}

trap cleanup EXIT ERR INT TERM

echo "=== Starting deletion protection test ==="
echo "Type: $TYPE"
echo "Name: $NAME"
echo "Namespace: $NAMESPACE"

# Get the instance namespace
echo "Getting instance namespace..."
ns=$(kubectl -n "$NAMESPACE" get "$TYPE" "$NAME" -oyaml | yq -r '.status.instanceNamespace')
echo "Instance namespace: $ns"

# Enable deletion protection
echo "Enabling deletion protection..."
kubectl -n "$NAMESPACE" patch "$TYPE" "$NAME" -p '{"spec":{"parameters":{"security":{"deletionProtection": true}}}}' --type merge

# Try to delete the instance (should fail)
echo "Attempting to delete protected instance..."
if ! kubectl -n "$NAMESPACE" delete "$TYPE" "$NAME"; then
  echo "✓ Instance protected - deletion blocked as expected"
else
  echo "✗ Instance got deleted! Deletion protection failed!"
  exit 1
fi

# Try to delete the namespace (should fail due to protection)
echo "Attempting to delete namespace in service cluster..."
if ! kubectl delete ns "$ns"; then
  echo "✓ Namespace protected - deletion blocked as expected"
else
  echo "✗ Namespace got deleted! Namespace protection failed!"
  exit 1
fi

echo "=== Deletion protection test completed successfully ==="
