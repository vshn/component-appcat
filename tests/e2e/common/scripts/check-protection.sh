#!/bin/bash

set -e

type="$1"
name="$2"

ns=$(kubectl -n "$NAMESPACE" get "$type" "$name" -oyaml | yq -r '.status.instanceNamespace')

if ! kubectl -n "$NAMESPACE" delete --timeout=30s "$type" "$name" ; then
  echo "instance protected"
else
  echo "instance got deleted! Please check deletion protection!"
  exit 1
fi

if ! kubectl delete --timeout=30s ns "$ns" ; then
  echo "namespace protected"
else
  echo "namespace got deleted! Please check deletion protection!"
  exit 1
fi

echo Returning with zero - Protections works well
exit 0