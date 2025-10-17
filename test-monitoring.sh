#!/bin/bash

# Test script for Prometheus monitoring setup
# This script checks if all metrics endpoints are reachable

echo "Testing MongoDB Community Search - Prometheus Setup"
echo "=================================================="

# Function to test endpoint
test_endpoint() {
    local url=$1
    local name=$2
    echo -n "Testing $name ($url): "
    
    if curl -s -f "$url" > /dev/null 2>&1; then
        echo "✅ OK"
        return 0
    else
        echo "❌ FAILED"
        return 1
    fi
}

# Function to test endpoint with content check
test_endpoint_with_content() {
    local url=$1
    local name=$2
    local expected_content=$3
    echo -n "Testing $name ($url): "
    
    response=$(curl -s "$url" 2>/dev/null)
    if [[ $? -eq 0 ]] && [[ "$response" == *"$expected_content"* ]]; then
        echo "✅ OK"
        return 0
    else
        echo "❌ FAILED"
        return 1
    fi
}

echo ""
echo "Basic connectivity tests:"
echo "-------------------------"

# Test basic endpoints
test_endpoint "http://localhost:9946/metrics" "Mongot Metrics"
test_endpoint "http://localhost:9216/metrics" "MongoDB Exporter Metrics"  
test_endpoint "http://localhost:9090" "Prometheus Web UI"
test_endpoint "http://localhost:3000" "Grafana Web UI"

echo ""
echo "Prometheus scraping tests:"
echo "--------------------------"

# Test Prometheus targets
test_endpoint_with_content "http://localhost:9090/api/v1/targets" "Prometheus Targets API" "mongot"

# Test that Prometheus can scrape mongot
test_endpoint_with_content "http://localhost:9090/api/v1/query?query=up%7Bjob%3D%22mongot%22%7D" "Mongot Target Status" "mongot"

# Test that Prometheus can scrape mongodb
test_endpoint_with_content "http://localhost:9090/api/v1/query?query=up%7Bjob%3D%22mongodb%22%7D" "MongoDB Target Status" "mongodb"

echo ""
echo "Metrics content tests:"
echo "----------------------"

# Test that mongot metrics contain expected content
test_endpoint_with_content "http://localhost:9946/metrics" "Mongot Metrics Content" "# HELP"

# Test that mongodb exporter metrics contain expected content  
test_endpoint_with_content "http://localhost:9216/metrics" "MongoDB Metrics Content" "mongodb_up"

echo ""
echo "Test completed!"
echo ""
echo "If all tests pass, your Prometheus monitoring setup is working correctly."
echo "You can now:"
echo "  • View metrics in Prometheus: http://localhost:9090"
echo "  • Create dashboards in Grafana: http://localhost:3000"
echo "  • Query metrics via Prometheus API or PromQL"