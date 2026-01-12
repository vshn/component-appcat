#!/bin/bash

set -e  # Exit on any error

NAMESPACE="${NAMESPACE:-appcat-e2e}"

echo "=== Finding SGCluster namespace for postgresql-e2e-test from control plane ==="

COMPOSITE_NAME=$(kubectl -n ${NAMESPACE} get vshnpostgresql postgresql-e2e-test -o jsonpath='{.spec.resourceRef.name}')
echo "Composite resource name: ${COMPOSITE_NAME}"

NAMESPACE=$(kubectl get namespace -l appcat.vshn.io/claim-name=postgresql-e2e-test -o jsonpath='{.items[0].metadata.name}')
echo "SGCluster namespace: ${NAMESPACE}"

if [ -z "$NAMESPACE" ]; then
  echo "ERROR: Could not find namespace for postgresql-e2e-test"
  exit 1
fi

# Check if pods exist before attempting restart
POD_COUNT=$(kubectl get pod -n ${NAMESPACE} -l app=StackGresCluster,stackgres.io/cluster-name=${COMPOSITE_NAME} --no-headers 2>/dev/null | wc -l)

if [ "$POD_COUNT" -eq 0 ]; then
  echo "ERROR: No SGCluster pods found in namespace ${NAMESPACE} with label stackgres.io/cluster-name=${COMPOSITE_NAME}"
  exit 1
fi

echo "=== Restarting ${POD_COUNT} SGCluster pod(s) in namespace ${NAMESPACE} on service cluster ==="
kubectl delete pod -n ${NAMESPACE} -l app=StackGresCluster,stackgres.io/cluster-name=${COMPOSITE_NAME}

echo "=== Waiting for SGCluster pods to restart ==="
kubectl wait --for=condition=ready pod -n ${NAMESPACE} -l app=StackGresCluster,stackgres.io/cluster-name=${COMPOSITE_NAME} --timeout=300s

echo "=== SGCluster restarted successfully ==="
