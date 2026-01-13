#!/bin/bash

set -ex

type="$1"
name="$2"
to_be_found="$3"

ns=$(kubectl -n "$NAMESPACE" get "$type" "$name" -oyaml | yq -r '.status.instanceNamespace')

kubectl -n "$ns" delete job --all --wait=true

# wait for cronjob to receive updated environment variables - it takes few reconciliations to update the envs
if [ "$to_be_found" == "b" ]; then
  while true; do
    vacuum_enabled=$(kubectl get -n "$ns" cronjobs.batch --ignore-not-found maintenancejob -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].env[?(@.name=="VACUUM_ENABLED")].value}')
    repack_enabled=$(kubectl get -n "$ns" cronjobs.batch --ignore-not-found maintenancejob -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].env[?(@.name=="REPACK_ENABLED")].value}')
    if [ "$vacuum_enabled" == "true" ] && [ "$repack_enabled" == "true" ]; then
      break
    fi
    echo "Waiting for envs: vacuum: True repack: True"
    sleep 15
  done
elif [ "$to_be_found" == "v" ]; then
  while true; do
    vacuum_enabled=$(kubectl get -n "$ns" cronjobs.batch --ignore-not-found maintenancejob -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].env[?(@.name=="VACUUM_ENABLED")].value}')
    repack_enabled=$(kubectl get -n "$ns" cronjobs.batch --ignore-not-found maintenancejob -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].env[?(@.name=="REPACK_ENABLED")].value}')
    if [ "$vacuum_enabled" == "true" ] && [ "$repack_enabled" == "false" ]; then
      break
    fi
    echo "Waiting for envs vacuum: True repack: False"
    sleep 15
  done
elif [ "$to_be_found" == "r" ]; then
  while true; do
    vacuum_enabled=$(kubectl get -n "$ns" cronjobs.batch --ignore-not-found maintenancejob -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].env[?(@.name=="VACUUM_ENABLED")].value}')
    repack_enabled=$(kubectl get -n "$ns" cronjobs.batch --ignore-not-found maintenancejob -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].env[?(@.name=="REPACK_ENABLED")].value}')
    if [ "$vacuum_enabled" == "false" ] && [ "$repack_enabled" == "true" ]; then
      break
    fi
    echo "Waiting for envs vacuum: False repack: True"
    sleep 15
  done
else
  echo "Invalid argument"
  exit 1
fi

# create a job itself
kubectl -n "$ns" create job --from cronjob/maintenancejob test

# wait until job is done
kubectl -n "$ns" wait --for=condition=complete --timeout=1000s job/test

# get job is for debugging purposes
# get specific job is to validate if job were created
# I have to wait for job/jobs completion otherwise stackgres will recreate that even if I delete it...
if [ "$to_be_found" == "r" ]; then
  kubectl -n "$ns" get job
  kubectl -n "$ns" wait --for=create job/databasesrepack
  kubectl -n "$ns" wait --for=condition=complete --timeout=1000s job/databasesrepack
elif [ "$to_be_found" == "v" ]; then
  kubectl -n "$ns" get job
  kubectl -n "$ns" wait --for=create job/vacuum
  kubectl -n "$ns" wait --for=condition=complete --timeout=1000s job/vacuum
elif [ "$to_be_found" == "b" ]; then
  kubectl -n "$ns" get job
  kubectl -n "$ns" wait --for=create job/databasesrepack
  kubectl -n "$ns" wait --for=create job/vacuum
  kubectl -n "$ns" wait --for=condition=complete --timeout=1000s job/databasesrepack
  kubectl -n "$ns" wait --for=condition=complete --timeout=1000s job/vacuum
else
  echo "Invalid argument"
  exit 1
fi
