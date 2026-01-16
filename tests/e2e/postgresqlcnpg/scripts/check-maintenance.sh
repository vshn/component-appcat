#!/bin/bash

set -ex

NAMESPACE="${NAMESPACE:-appcat-e2e}"
ns=$(kubectl -n "$NAMESPACE" get vshnpostgresql pg-cnpg-e2e  -oyaml | yq -r '.status.instanceNamespace')

# Initial maintenance should be completed
job=$(kubectl -n "$ns" get job -o name | grep "initial-maintenance")
kubectl -n "$ns" wait --for=condition=complete --timeout=1000s $job

# Try vacuum
vacuum_enabled=$(kubectl get -n "$ns" cronjobs.batch --ignore-not-found maintenancejob -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].env[?(@.name=="VACUUM_ENABLED")].value}')
[ "$vacuum_enabled" == "true" ]

while true; do
  instance=$(kubectl -n "$ns" get cluster -o yaml | yq -r .items[0].status.readyInstances)
  # Check that instances are >0
  if [ "$instance" -gt 0 ]; then
    break
  fi
  echo "Waiting for cluster to start reporting ready instances..."
  sleep 10
done

kubectl -n "$ns" create job --from=cronjob/maintenancejob manual-maintenance-job
kubectl -n "$ns" wait --for=condition=complete --timeout=1000s job/manual-maintenance-job

# Check that the job is reporting "vacuuming database" in its logs
kubectl -n "$ns" logs job/manual-maintenance-job | grep -i "vacuuming database" || (echo "Vacuuming not found in logs" && exit 1)
