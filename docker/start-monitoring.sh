#!/bin/bash

# MongoDB Community Search - Prometheus Monitoring Setup
# This script starts the full stack with Prometheus monitoring

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Run docker compose from the docker/ directory so compose file is found automatically
cd "$SCRIPT_DIR"

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

# Returns 0 (true) if Docker volume does not exist or exists but has no files
is_volume_empty() {
    local volume_name="$1"
    local full_volume="mdb-community-search_${volume_name}"

    if ! docker volume inspect "$full_volume" >/dev/null 2>&1; then
        return 0
    fi

    if [ -z "$(docker run --rm -v "${full_volume}:/data" alpine sh -c 'ls -A /data 2>/dev/null')" ]; then
        return 0
    fi

    return 1
}

# Run setup first if auth-files volume is empty
if is_volume_empty "auth-files"; then
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
sleep 30

# Run monitoring tests
echo ""
echo "🧪 Running monitoring tests..."
echo "=============================="
if [ -x "$REPO_ROOT/scripts/test-monitoring.sh" ]; then
    "$REPO_ROOT/scripts/test-monitoring.sh"
else
    echo "⚠️  scripts/test-monitoring.sh not found or not executable"
    echo "   Run 'chmod +x scripts/test-monitoring.sh' to make it executable"
fi

# First, test dashboard query availability (no-data tolerant by default)
echo "🧪 Running dashboard metrics test (no-data mode)..."
if [ -x "$REPO_ROOT/scripts/test-dashboard-metrics.sh" ]; then
    cd "$REPO_ROOT/scripts"
    ./test-dashboard-metrics.sh
    cd "$REPO_ROOT"
else
    echo "⚠️  scripts/test-dashboard-metrics.sh not found or not executable"
    echo "   Run 'chmod +x scripts/test-dashboard-metrics.sh' to make it executable"
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
    if [ -x "$REPO_ROOT/scripts/generate-metrics.sh" ]; then
        "$REPO_ROOT/scripts/generate-metrics.sh" compose

        echo ""
        echo "🧪 Running strict dashboard metrics test after data generation..."
        if [ -x "$REPO_ROOT/scripts/test-dashboard-metrics.sh" ]; then
            cd "$REPO_ROOT/scripts"
            ./test-dashboard-metrics.sh --strict
            cd "$REPO_ROOT"
        else
            echo "⚠️  scripts/test-dashboard-metrics.sh not found or not executable"
            echo "   Run 'chmod +x scripts/test-dashboard-metrics.sh' to make it executable"
        fi

        if [ $? -ne 0 ]; then
            echo "❌ Strict dashboard metrics test failed after data generation."
            exit 1
        fi
    else
        echo "⚠️  scripts/generate-metrics.sh not found or not executable"
        echo "   Run 'chmod +x scripts/generate-metrics.sh' to make it executable"
        echo "   Then run: ./scripts/generate-metrics.sh compose"
    fi
else
    echo ""
    echo "💡 To populate your search indexes and metrics with test data later, run: ./scripts/generate-metrics.sh compose"
fi

echo ""