#!/bin/bash

set -e

type="$1"
name="$2"

# Downsize
set +e
kubectl -n "$NAMESPACE" patch "$type" "$name" \
    --dry-run=server \
    -p '{"spec":{"parameters":{"size":{"disk":"1Gi"}}}}' \
    --type merge
downsize_exit_code=$?
set -e

if [[ $downsize_exit_code -eq 0 ]]; then
    echo "ERROR: Downsize was allowed"
    exit 1
else
    echo "SUCCESS: Downsize was blocked"
fi

# Upsize
set +e
kubectl -n "$NAMESPACE" patch "$type" "$name" \
    --dry-run=server \
    -p '{"spec":{"parameters":{"size":{"disk":"100Gi"}}}}' \
    --type merge
upsize_exit_code=$?
set -e

if [[ $upsize_exit_code -ne 0 ]]; then
    echo "ERROR: Upsizing was blocked"
    exit 1
else
    echo "SUCCESS: Upsize was allowed."
fi
