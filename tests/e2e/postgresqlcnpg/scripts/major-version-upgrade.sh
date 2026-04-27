#!/usr/bin/env bash
set -ex

NAMESPACE="${NAMESPACE:-appcat-e2e}"
RESOURCE="pg-cnpg-e2e"
DEADLINE=$(($(date +%s) + 1800))

CURRENT=$(kubectl get vshnpostgresql "$RESOURCE" -n "$NAMESPACE" -o jsonpath='{.status.currentVersion}')
TARGET=$((CURRENT + 1))

echo "Upgrading PostgreSQL major version: $CURRENT -> $TARGET"

kubectl patch vshnpostgresql "$RESOURCE" -n "$NAMESPACE" --type=merge \
  -p "{\"spec\":{\"parameters\":{\"service\":{\"majorVersion\":\"$TARGET\"}}}}"

ns=$(kubectl -n "$NAMESPACE" get vshnpostgresql "$RESOURCE" -o jsonpath='{.status.instanceNamespace}')

# Wait for composition function to reconcile and update the imageCatalogRef
kubectl wait --for=jsonpath='{.spec.imageCatalogRef.major}'="$TARGET" \
  clusters.postgresql.cnpg.io/postgresql -n "$ns" --timeout=300s

# Poll DB directly - cluster phase can briefly show healthy before pg_upgrade starts
while true; do
  PG_POD=$(kubectl get pods -n "$ns" -l "cnpg.io/cluster=postgresql,role=primary" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  DB_VERSION=$(kubectl exec -n "$ns" "$PG_POD" -- psql -U postgres -t -c "SHOW server_version_num;" 2>/dev/null | tr -d ' \n' || true)
  DB_MAJOR=${DB_VERSION:0:2}
  echo "DB server_version_num=$DB_VERSION, major=$DB_MAJOR, expected=$TARGET"
  if [ "$DB_MAJOR" = "$TARGET" ]; then
    echo "OK: PostgreSQL upgraded to version $TARGET. DB confirmed."

    echo "Verifying data integrity after upgrade..."
    DATA=$(kubectl exec -n "$ns" "$PG_POD" -- psql -U postgres -t -A -c \
      "SELECT marker FROM e2e_restore_test WHERE marker = 'cnpg-restore-check';" 2>/dev/null || true)
    if [ "$DATA" != "cnpg-restore-check" ]; then
      echo "FAIL: Data not found after upgrade. Got: '$DATA'"
      exit 1
    fi
    echo "OK: Data intact after major version upgrade."
    exit 0
  fi
  if [ $(date +%s) -gt $DEADLINE ]; then
    echo "FAIL: timeout waiting for DB version $TARGET (last: $DB_MAJOR)"
    exit 1
  fi
  sleep 5
done
