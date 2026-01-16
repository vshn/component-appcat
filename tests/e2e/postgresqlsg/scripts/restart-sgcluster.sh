#!/bin/bash

set -e  # Exit on any error

NAMESPACE="${NAMESPACE:-appcat-e2e}"

echo "=== Finding SGCluster namespace for pg-sg-e2e from control plane ==="

COMPOSITE_NAME=$(kubectl -n ${NAMESPACE} get vshnpostgresql pg-sg-e2e -o jsonpath='{.spec.resourceRef.name}')
echo "Composite resource name: ${COMPOSITE_NAME}"

INSTANCE_NAMESPACE=$(kubectl -n "$NAMESPACE" get vshnpostgresql pg-sg-e2e -oyaml | yq -r '.status.instanceNamespace')
echo "SGCluster namespace: ${INSTANCE_NAMESPACE}"

if [ -z "$INSTANCE_NAMESPACE" ]; then
  echo "ERROR: Could not find namespace for pg-sg-e2e"
  exit 1
fi

# Check if pods exist before attempting restart
POD_COUNT=$(kubectl get pod -n ${INSTANCE_NAMESPACE} -l app=StackGresCluster,stackgres.io/cluster-name=${COMPOSITE_NAME} --no-headers 2>/dev/null | wc -l)

if [ "$POD_COUNT" -eq 0 ]; then
  echo "ERROR: No SGCluster pods found in namespace ${INSTANCE_NAMESPACE} with label stackgres.io/cluster-name=${COMPOSITE_NAME}"
  exit 1
fi

echo "=== Restarting ${POD_COUNT} SGCluster pod(s) in namespace ${INSTANCE_NAMESPACE} on service cluster ==="
kubectl delete pod -n ${INSTANCE_NAMESPACE} -l app=StackGresCluster,stackgres.io/cluster-name=${COMPOSITE_NAME}

echo "=== Waiting for SGCluster pods to restart ==="
kubectl wait --for=condition=ready pod -n ${INSTANCE_NAMESPACE} -l app=StackGresCluster,stackgres.io/cluster-name=${COMPOSITE_NAME} --timeout=300s

echo "=== SGCluster restarted successfully ==="
