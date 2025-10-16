#!/bin/bash

# MongoDB Community Search - Prometheus Monitoring Setup
# This script starts the full stack with Prometheus monitoring

set -e

echo "Starting MongoDB Community Search with Prometheus monitoring..."

# Check if network exists, create if not
if ! docker network ls | grep -q "search-community"; then
    echo "Creating search-community network..."
    docker network create search-community
fi

# Set default passwords if not provided
export ADMIN_PASSWORD=${ADMIN_PASSWORD:-admin}
export MONGOT_PASSWORD=${MONGOT_PASSWORD:-mongotPassword}
export GRAFANA_PASSWORD=${GRAFANA_PASSWORD:-admin}

echo "Using passwords:"
echo "  MongoDB Admin: [HIDDEN]"
echo "  Mongot User: [HIDDEN]"
echo "  Grafana Admin: [HIDDEN]"

# Run setup first if keyfile doesn't exist
if [ ! -f keyfile ]; then
    echo "Running initial setup..."
    docker compose --profile setup up setup-generator
    echo "Setup completed."
fi

# Start the main services
echo "Starting all services..."
docker compose up -d mongod mongot mongodb-exporter prometheus grafana

echo ""
echo "Services started! Access points:"
echo "  MongoDB:           mongodb://admin:${ADMIN_PASSWORD}@localhost:27017"
echo "  Mongot gRPC:       localhost:27028"
echo "  Mongot Health:     http://localhost:8080"
echo "  Mongot Metrics:    http://localhost:9946/metrics"
echo "  MongoDB Exporter:  http://localhost:9216/metrics"
echo "  Prometheus:        http://localhost:9090"
echo "  Grafana:          http://localhost:3000 (admin/${GRAFANA_PASSWORD})"
echo ""
echo "Wait for services to be healthy, then you can:"
echo "  1. View metrics directly in Prometheus at http://localhost:9090"
echo "  2. Create dashboards in Grafana at http://localhost:3000"
echo "  3. Query MongoDB metrics: mongodb_* (from exporter)"
echo "  4. Query Mongot metrics: mongot_* (native)"
echo ""