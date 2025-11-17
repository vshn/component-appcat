#!/bin/bash

set -e

name="$1"

NAMESPACE="${NAMESPACE:-appcat-e2e}"

echo "=== Starting PostgreSQL CNPG connection test ==="
echo "Namespace: $NAMESPACE"
echo "Instance name: $name"

# Decode and setup kubeconfigs
echo "$CONTROL_PLANE_KUBECONFIG_CONTENT" | base64 -d > /tmp/control-plane-config
echo "$SERVICE_CLUSTER_KUBECONFIG_CONTENT" | base64 -d > /tmp/service-cluster-config

export KUBECONFIG=/tmp/control-plane-config
echo "Using control plane kubeconfig"

echo "Getting connection details..."
instancens=$(kubectl -n "$NAMESPACE" get vshnpostgresql "$name" -oyaml | yq -r '.status.instanceNamespace')
comp=$(kubectl -n "$NAMESPACE" get vshnpostgresql "$name" -oyaml | yq -r '.spec.resourceRef.name')

echo "Instance namespace: $instancens"
echo "Composite name: $comp"

# Switch to service cluster kubeconfig for database operations
export KUBECONFIG=/tmp/service-cluster-config
echo "Using service cluster kubeconfig for database operations"

# Detect if running in OpenShift
KUBECTL_ARGS=""
if kubectl api-resources | grep -q "openshift.io"; then
    echo "OpenShift detected, using --as=cluster-admin"
    KUBECTL_ARGS="--as=cluster-admin"
fi

echo "Getting database credentials from secret..."
secret_name="${comp}-cluster-app"
db_host="${comp}-cluster-rw"
db_port="5432"
db_name="app"

# Wait for secret to be available
timeout=300
elapsed=0
while ! kubectl ${KUBECTL_ARGS} -n "$instancens" get secret "$secret_name" &>/dev/null; do
    if [ $elapsed -ge $timeout ]; then
        echo "✗ Timeout waiting for secret $secret_name"
        exit 1
    fi
    echo "Waiting for secret $secret_name to be available..."
    sleep 5
    elapsed=$((elapsed + 5))
done

db_user=$(kubectl ${KUBECTL_ARGS} -n "$instancens" get secret "$secret_name" -o jsonpath='{.data.username}' | base64 -d)
db_password=$(kubectl ${KUBECTL_ARGS} -n "$instancens" get secret "$secret_name" -o jsonpath='{.data.password}' | base64 -d)

echo "Database connection details retrieved"
echo "  Host: $db_host"
echo "  Port: $db_port"
echo "  Database: $db_name"
echo "  User: $db_user"

# Wait for PostgreSQL pod to be ready
echo "Waiting for PostgreSQL cluster to be ready..."
timeout=300
elapsed=0
while ! kubectl ${KUBECTL_ARGS} -n "$instancens" get pods -l "cnpg.io/cluster=${comp}-cluster" -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; do
    if [ $elapsed -ge $timeout ]; then
        echo "✗ Timeout waiting for PostgreSQL pod"
        kubectl ${KUBECTL_ARGS} -n "$instancens" get pods -l "cnpg.io/cluster=${comp}-cluster"
        exit 1
    fi
    echo "Waiting for PostgreSQL pod to be ready..."
    sleep 5
    elapsed=$((elapsed + 5))
done

echo "PostgreSQL pod is running"

# Get the first running pod
pod_name=$(kubectl ${KUBECTL_ARGS} -n "$instancens" get pods -l "cnpg.io/cluster=${comp}-cluster,role=primary" -o jsonpath='{.items[0].metadata.name}')
echo "Using pod: $pod_name"

# Test database connection and create test data
echo "Testing database connection..."
kubectl ${KUBECTL_ARGS} -n "$instancens" exec -i "$pod_name" -- psql -U "$db_user" -d "$db_name" <<EOF
-- Create test table if not exists
CREATE TABLE IF NOT EXISTS e2e_test (
    id SERIAL PRIMARY KEY,
    data TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert test data
INSERT INTO e2e_test (data) VALUES ('test-data-cnpg-$(date +%s)');

-- Verify data
SELECT COUNT(*) as row_count FROM e2e_test;
EOF

if [ $? -eq 0 ]; then
    echo "✓ Database connection successful and test data created"
else
    echo "✗ Database connection failed"
    exit 1
fi

echo "=== PostgreSQL CNPG connection test completed successfully ==="
