#!/bin/bash

set -e

NAMESPACE="${NAMESPACE:-appcat-e2e}"

echo "=== Starting Keycloak custom volumes test ==="
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

echo "Checking if test-cm ConfigMap is mounted..."
kubectl get statefulset $sts -n "$ns" \
  -o jsonpath='{.spec.template.spec.volumes[*].configMap.name}' | grep test-cm

echo "Checking if test-secret Secret is mounted..."
kubectl get statefulset $sts -n "$ns" \
  -o jsonpath='{.spec.template.spec.volumes[*].secret.secretName}' | grep test-secret

echo "Checking ConfigMap mount path..."
kubectl get statefulset $sts -n "$ns" \
  -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[*].mountPath}' | grep /custom/configs/test-cm

echo "Checking Secret mount path..."
kubectl get statefulset $sts -n "$ns" \
  -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[*].mountPath}' | grep /custom/secrets/test-secret

pod="${sts}-0"
KUBECTL_ARGS=""
if kubectl api-resources | grep -q "openshift.io"; then
    echo "OpenShift detected, using --as=cluster-admin"
    KUBECTL_ARGS="--as=cluster-admin"
fi

echo "Verifying directories exist in pod $pod..."
kubectl ${KUBECTL_ARGS} -n "$ns" exec "$pod" -- test -d /custom/configs/test-cm
kubectl ${KUBECTL_ARGS} -n "$ns" exec "$pod" -- test -d /custom/secrets/test-secret

echo "✓ All custom volumes tests passed"
echo "=== Keycloak custom volumes test completed successfully ==="
