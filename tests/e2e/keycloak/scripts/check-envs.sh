#!/bin/bash
set -e

name=$(kubectl -n $NAMESPACE get vshnkeycloak keycloak-e2e -o jsonpath='{.spec.resourceRef.name}')
sts="${name}-keycloakx"
ns=$(kubectl -n "$NAMESPACE" get vshnkeycloak keycloak-e2e -o yaml | yq -r '.status.instanceNamespace')
pod="${sts}-0"

kubectl get statefulset "$sts" -n "$ns" \
  -o jsonpath='{.spec.template.spec.containers[0].envFrom[*].configMapRef.name}' | grep env-from-cm

kubectl get statefulset "$sts" -n "$ns" \
  -o jsonpath='{.spec.template.spec.containers[0].envFrom[*].secretRef.name}' | grep env-from-secret

kubectl -n "$ns" exec "$pod" -- /bin/env | grep KC_MY_ENV_FROM_CM
kubectl -n "$ns" exec "$pod" -- /bin/env | grep KC_MY_ENV_FROM_SECRET
kubectl -n "$ns" exec "$pod" -- /bin/env | grep KC_MY_ENV_FROM_SECRET_DEPRECATED
