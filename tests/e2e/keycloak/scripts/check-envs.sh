#!/bin/bash

set -e

NAMESPACE="${NAMESPACE:-appcat-e2e}"

echo "=== Starting Keycloak environment variables test ==="
echo "Namespace: $NAMESPACE"

echo "Getting instance details..."
name=$(kubectl -n $NAMESPACE get vshnkeycloak keycloak-e2e -o jsonpath='{.spec.resourceRef.name}')
ns=$(kubectl -n "$NAMESPACE" get vshnkeycloak keycloak-e2e -o jsonpath='{.status.instanceNamespace}')

if [ -z "$name" ] || [ -z "$ns" ]; then
  echo "✗ ERROR: Could not retrieve instance name or namespace"
  exit 1
fi

echo "Instance name: $name"
echo "Instance namespace: $ns"

sts="${name}-keycloakx"
pod="${sts}-0"

echo "Checking if env-from-cm ConfigMap is referenced..."
kubectl get statefulset "$sts" -n "$ns" \
  -o jsonpath='{.spec.template.spec.containers[0].envFrom[*].configMapRef.name}' | grep env-from-cm

echo "Checking if env-from-secret Secret is referenced..."
kubectl get statefulset "$sts" -n "$ns" \
  -o jsonpath='{.spec.template.spec.containers[0].envFrom[*].secretRef.name}' | grep env-from-secret

KUBECTL_ARGS=""
if kubectl api-resources | grep -q "openshift.io"; then
    echo "OpenShift detected, using --as=cluster-admin"
    KUBECTL_ARGS="--as=cluster-admin"
fi
echo "Verifying environment variables in pod $pod..."
kubectl ${KUBECTL_ARGS} -n "$ns" exec "$pod" -- /bin/env | grep KC_MY_ENV_FROM_CM
kubectl ${KUBECTL_ARGS} -n "$ns" exec "$pod" -- /bin/env | grep KC_MY_ENV_FROM_SECRET
kubectl ${KUBECTL_ARGS} -n "$ns" exec "$pod" -- /bin/env | grep KC_MY_ENV_FROM_SECRET_DEPRECATED

echo "✓ All environment variable tests passed"
echo "=== Keycloak environment variables test completed successfully ==="
