#!/bin/bash

# Test script for Prometheus monitoring setup
# This script checks if all metrics endpoints are reachable

FAILED_TESTS=0
RETRY_ATTEMPTS="${RETRY_ATTEMPTS:-20}"
RETRY_DELAY_SECONDS="${RETRY_DELAY_SECONDS:-2}"

retry_until_success() {
    local command="$1"
    local attempts="${2:-$RETRY_ATTEMPTS}"
    local delay="${3:-$RETRY_DELAY_SECONDS}"

    local try
    for try in $(seq 1 "$attempts"); do
        if eval "$command" >/dev/null 2>&1; then
            return 0
        fi

        if [[ "$try" -lt "$attempts" ]]; then
            sleep "$delay"
        fi
    done

    return 1
}

echo "Testing MongoDB Community Search - Prometheus Setup"
echo "=================================================="

# Function to test endpoint
test_endpoint() {
    local url=$1
    local name=$2
    echo -n "Testing $name ($url): "

    if retry_until_success "curl -s -f '$url'"; then
        echo "✅ OK"
        return 0
    else
        echo "❌ FAILED"
        ((FAILED_TESTS++))
        return 1
    fi
}

# Function to test endpoint with content check
test_endpoint_with_content() {
    local url=$1
    local name=$2
    local expected_content=$3
    echo -n "Testing $name ($url): "

    if retry_until_success "response=\$(curl -s '$url' 2>/dev/null) && [[ \"\$response\" == *\"$expected_content\"* ]]"; then
        echo "✅ OK"
        return 0
    else
        echo "❌ FAILED"
        ((FAILED_TESTS++))
        return 1
    fi
}

echo ""
echo "Basic connectivity tests:"
echo "-------------------------"

# Test basic endpoints
test_endpoint "http://localhost:8080/health" "MongoDB Search Health"
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

# Test that Prometheus can scrape mongodb exporter
test_endpoint_with_content "http://localhost:9090/api/v1/query?query=up%7Bjob%3D%22mongodb-exporter%22%7D" "MongoDB Exporter Target Status" "mongodb-exporter"

echo ""
echo "Metrics content tests:"
echo "----------------------"

# Test that mongot metrics contain expected content
test_endpoint_with_content "http://localhost:9946/metrics" "Mongot Metrics Content" "# HELP"

# Test that mongodb exporter metrics contain expected content  
test_endpoint_with_content "http://localhost:9216/metrics" "MongoDB Metrics Content" "mongodb_up"

echo ""
if [[ $FAILED_TESTS -eq 0 ]]; then
echo "✅ Test completed successfully!"
echo ""
echo "If all tests pass, your Prometheus monitoring setup is working correctly."
echo "You can now:"
echo "  • View metrics in Prometheus: http://localhost:9090"
echo "  • Create dashboards in Grafana: http://localhost:3000"
echo "  • Query metrics via Prometheus API or PromQL"
exit 0
fi

echo "❌ Test completed with $FAILED_TESTS failed check(s)."
exit 1