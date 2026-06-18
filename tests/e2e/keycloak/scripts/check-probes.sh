#!/bin/bash

# Verifies that Keycloak health probes honour a custom service.relativePath.
# The instance is installed with relativePath: /auth (see 70-install.yaml), so
# all probes must target /auth/health* and the StatefulSet must roll out Ready,
# which only happens when the probes actually hit the right endpoints.

set -e

NAMESPACE="${NAMESPACE:-appcat-e2e}"
EXPECTED_BASE="/auth"

echo "=== Starting Keycloak probe path test ==="
echo "Namespace: $NAMESPACE"

echo "Getting instance namespace..."
ns=$(kubectl -n "$NAMESPACE" get vshnkeycloak keycloak-e2e -o jsonpath='{.status.instanceNamespace}')

if [ -z "$ns" ]; then
  echo "✗ ERROR: Could not retrieve instance namespace"
  exit 1
fi

echo "Instance namespace: $ns"

echo "Getting composite name..."
comp=$(kubectl -n "$NAMESPACE" get vshnkeycloak keycloak-e2e -o jsonpath='{.spec.resourceRef.name}')

if [ -z "$comp" ]; then
  echo "✗ ERROR: Could not retrieve composite name"
  exit 1
fi

sts="${comp}-keycloakx"
echo "StatefulSet: $sts"

probe_path() {
  kubectl -n "$ns" get statefulset "$sts" \
    -o jsonpath="{.spec.template.spec.containers[?(@.name=='keycloak')].${1}.httpGet.path}" 2>/dev/null
}

# The instance was first created with the default relativePath and is updated to
# /auth in 70-install.yaml. Wait until Crossplane/Helm have pushed the new probe
# path onto the StatefulSet before asserting, otherwise we may read the old spec.
echo "Waiting for probe paths to pick up relativePath '$EXPECTED_BASE'..."
for _ in $(seq 1 60); do
  [[ "$(probe_path livenessProbe)" == "$EXPECTED_BASE/health"* ]] && break
  sleep 5
done

echo "Checking probe paths..."
for probe in livenessProbe readinessProbe startupProbe; do
  path=$(probe_path "$probe")
  echo "  $probe path: $path"
  if [[ "$path" != "$EXPECTED_BASE/health"* ]]; then
    echo "✗ ERROR: $probe path '$path' does not start with '$EXPECTED_BASE/health'"
    exit 1
  fi
done

echo "✓ All probe paths honour relativePath '$EXPECTED_BASE'"

# A successful rollout proves the probes actually pass against /auth/health*,
# since pods only become Ready when the readiness probe hits the right path.
echo "Waiting for StatefulSet rollout (probes must pass for pods to become Ready)..."
kubectl -n "$ns" rollout status statefulset "$sts" --timeout=900s

echo "✓ Keycloak became Ready with custom relativePath probes"
echo "=== Keycloak probe path test completed successfully ==="
