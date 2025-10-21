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
    docker compose run --rm setup-generator
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
echo "Waiting for services to be ready..."
sleep 10

# Run monitoring tests
echo ""
echo "🧪 Running monitoring tests..."
echo "=============================="
if [ -x "./test-monitoring.sh" ]; then
    ./test-monitoring.sh
else
    echo "⚠️  test-monitoring.sh not found or not executable"
    echo "   Run 'chmod +x test-monitoring.sh' to make it executable"
fi

# First, test that all dashboard metrics are available
echo "🧪 Running dashboard metrics test to check all dashboard metrics return..."
if [ -x "./grafana/test-dashboard-metrics.sh" ]; then
    ./grafana/test-dashboard-metrics.sh
else
    echo "⚠️  grafana/test-dashboard-metrics.sh not found or not executable"
    echo "   Run 'chmod +x grafana/test-dashboard-metrics.sh' to make it executable"
fi

# Check if the test passed
if [ $? -ne 0 ]; then
    echo "❌ Dashboard metrics test failed. Please ensure all services are running properly."
    exit 1
fi

echo ""

echo ""
echo "📊 Setup complete! You can now:"
echo "  1. View metrics directly in Prometheus at http://localhost:9090"
echo "  2. Create dashboards in Grafana at http://localhost:3000"
echo "  3. Query MongoDB metrics: mongodb_* (from exporter)"
echo "  4. Query Mongot metrics: mongot_* (native)"
echo ""

# Ask user if they want to generate test data
echo "🎯 Would you like to generate test data and metrics now? This will:"
echo "   • Create search indexes on sample movie data"
echo "   • Run search queries to populate dashboard metrics"
echo "   • Make the Grafana dashboard show real data"
echo ""
read -p "Generate test metrics? (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "🚀 Generating test metrics..."
    if [ -x "./generate-metrics.sh" ]; then
        ./generate-metrics.sh
    else
        echo "⚠️  generate-metrics.sh not found or not executable"
        echo "   Run 'chmod +x generate-metrics.sh' to make it executable"
        echo "   Then run: ./generate-metrics.sh"
    fi
else
    echo ""
    echo "💡 To populate your search indexes and metrics with test data later, run: ./generate-metrics.sh"
fi

echo ""