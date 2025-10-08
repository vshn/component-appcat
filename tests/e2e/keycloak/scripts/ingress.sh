#!/bin/bash

set -e

NAMESPACE="${NAMESPACE:-appcat-e2e}"

echo "=== Starting Keycloak ingress test ==="
echo "Namespace: $NAMESPACE"

# Decode and setup kubeconfigs
echo "$CONTROL_PLANE_KUBECONFIG_CONTENT" | base64 -d > /tmp/control-plane-config
echo "$SERVICE_CLUSTER_KUBECONFIG_CONTENT" | base64 -d > /tmp/service-cluster-config

# Use control plane kubeconfig to get instance namespace
export KUBECONFIG=/tmp/control-plane-config
echo "Using control plane kubeconfig for instance operations"

echo "Getting instance namespace..."
ns=$(kubectl -n "$NAMESPACE" get vshnkeycloak keycloak-e2e -o jsonpath='{.status.instanceNamespace}')

if [ -z "$ns" ]; then
  echo "✗ ERROR: Could not retrieve instance namespace"
  exit 1
fi

echo "Instance namespace: $ns"

# Switch to service cluster kubeconfig for ingress operations
export KUBECONFIG=/tmp/service-cluster-config
echo "Using service cluster kubeconfig for ingress operations"

echo "Getting ingress FQDN..."
fqdn=$(kubectl -n "$ns" get ingress -o jsonpath='{.items[0].spec.tls[0].hosts[0]}')

if [ -z "$fqdn" ]; then
  echo "✗ ERROR: Could not retrieve FQDN from ingress"
  exit 1
fi

echo "Found FQDN: $fqdn"
echo "Expected FQDN: keycloak-e2e.example.com"

if [[ "$fqdn" == "keycloak-e2e.example.com" ]]; then
  echo "✓ FQDN matches expected value"
else
  echo "✗ ERROR: FQDN mismatch"
  exit 1
fi

echo "=== Keycloak ingress test completed successfully ==="
