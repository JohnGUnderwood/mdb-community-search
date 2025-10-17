#!/bin/bash

# Test script to validate that all metrics used in the Grafana dashboard are available

echo "🔍 Testing Dashboard Metrics..."
echo "================================"

# Initialize failure counter
FAILED_TESTS=0

# Function to test metric availability
test_metric() {
    local query=$1
    local name=$2
    local optional=${3:-false}
    echo -n "Testing $name: "
    
    if curl -s "http://localhost:9090/api/v1/query?query=$query" | jq -r '.data.result[0].value[1]' >/dev/null 2>&1; then
        echo "✅ Available"
        return 0
    else
        if [[ "$optional" == "true" ]]; then
            echo "❌ Not available (optional - expected if no search queries have been made)"
        else
            echo "❌ Not available"
            ((FAILED_TESTS++))
        fi
        return 1
    fi
}

# Function to test metric with result array check
test_metric_with_array() {
    local query=$1
    local name=$2
    local search_term=$3
    echo -n "Testing $name: "
    
    if curl -s "http://localhost:9090/api/v1/query?query=$query" | jq -r '.data.result' | grep -q "$search_term" 2>/dev/null; then
        echo "✅ Available"
        return 0
    else
        echo "❌ Not available"
        ((FAILED_TESTS++))
        return 1
    fi
}

# Test MongoDB Up metric
test_metric "mongodb_up" "mongodb_up"

# Test MongoDB Connections
test_metric_with_array "mongodb_ss_connections" "mongodb_ss_connections" "current"

# Test MongoDB Operations
test_metric_with_array "mongodb_ss_opcounters" "mongodb_ss_opcounters" "insert"

# Test MongoDB Memory
test_metric "mongodb_ss_mem_resident" "mongodb_ss_mem_resident"

# Test MongoDB Network
test_metric "mongodb_ss_network_bytesIn" "mongodb_ss_network_bytesIn"

# Test Mongot Metrics (optional - might not be available if no searches have been made)
test_metric "mongot_command_searchBetaCommandTotalLatency_seconds" "mongot_command_searchBetaCommandTotalLatency_seconds" "true"

# Test Mongot Service Status 
test_metric "up%7Bjob%3D%22mongot%22%7D" "up{job=\"mongot\"}"

# Test Database Stats
test_metric_with_array "mongodb_dbstats_collections" "mongodb_dbstats_collections" "database"

# Test WiredTiger Cache
test_metric "mongodb_ss_wt_cache_bytes_currently_in_the_cache" "mongodb_ss_wt_cache_bytes_currently_in_the_cache"

echo ""
echo "✨ Dashboard metric validation complete!"
echo ""

# Report results and exit with appropriate code
if [[ $FAILED_TESTS -eq 0 ]]; then
    echo "🎉 All required dashboard metrics are available!"
    echo ""
    echo "📊 To view the dashboard, open Grafana at: http://localhost:3000"
    echo "   - Username: admin"
    echo "   - Password: ${GRAFANA_PASSWORD:-admin}"
    echo "   - Dashboard: 'MongoDB Community Search Monitoring'"
    exit 0
else
    echo "💥 $FAILED_TESTS required dashboard metric(s) failed!"
    echo ""
    echo "🔧 Troubleshooting steps:"
    echo "   1. Ensure MongoDB and Mongot services are running"
    echo "   2. Check that Prometheus is scraping metrics successfully"
    echo "   3. Verify MongoDB exporter is configured correctly"
    echo "   4. Run ./test-monitoring.sh to check basic connectivity"
    echo ""
    echo "📊 Dashboard may not display correctly until all metrics are available."
    exit 1
fi