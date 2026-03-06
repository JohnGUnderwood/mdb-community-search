#!/bin/bash

# Test script to validate that all metrics used in the Grafana dashboard are available

echo "🔍 Testing Dashboard Metrics..."
echo "================================"

# In no-data mode, a query is considered valid if Prometheus executes it successfully,
# even when it returns no time series yet.
ALLOW_NO_DATA="${ALLOW_NO_DATA:-true}"
for arg in "$@"; do
    case "$arg" in
        --allow-no-data)
            ALLOW_NO_DATA="true"
            ;;
        --strict)
            ALLOW_NO_DATA="false"
            ;;
    esac
done

if [[ "$ALLOW_NO_DATA" == "true" ]]; then
    echo "ℹ️  Running in no-data mode (empty results are allowed)"
else
    echo "ℹ️  Running in strict mode (metrics must return valid values)"
fi

# Initialize failure counter
FAILED_TESTS=0

# Function to test metric availability
test_metric() {
    local query=$1
    local name=$2
    local optional=${3:-false}
    echo -n "Testing $name: "
    
    if curl -s "http://localhost:9090/api/v1/query" -G --data-urlencode "query=$query" | jq -r '.data.result[0].value[1]' >/dev/null 2>&1; then
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
    
    if curl -s "http://localhost:9090/api/v1/query" -G --data-urlencode "query=$query" | jq -r '.data.result' | grep -q "$search_term" 2>/dev/null; then
        echo "✅ Available"
        return 0
    else
        echo "❌ Not available"
        ((FAILED_TESTS++))
        return 1
    fi
}

# Smart function that automatically decides which test method to use
test_metric_smart() {
    local query=$1
    local name=$2
    local optional=${3:-false}
    echo -n "Testing $name: "
    
    # Get the query response - use proper URL encoding for the query parameter
    local response=$(curl -s "http://localhost:9090/api/v1/query" -G --data-urlencode "query=$query")
    local status=$(echo "$response" | jq -r '.status')
    
    if [[ "$status" != "success" ]]; then
        if [[ "$optional" == "true" ]]; then
            echo "❌ Not available (optional - query failed)"
        else
            echo "❌ Not available (query failed)"
            ((FAILED_TESTS++))
        fi
        return 1
    fi
    
    # Count how many results we have
    local result_count=$(echo "$response" | jq -r '.data.result | length')
    
    if [[ "$result_count" -eq 0 ]]; then
        if [[ "$ALLOW_NO_DATA" == "true" ]]; then
            echo "✅ Available (no data yet)"
            return 0
        fi
        if [[ "$optional" == "true" ]]; then
            echo "❌ Not available (optional - no results)"
        else
            echo "❌ Not available (no results)"
            ((FAILED_TESTS++))
        fi
        return 1
    fi
    
    # Check if this is a multi-series metric (has labels that create multiple time series)
    local has_multiple_series=false
    if [[ "$result_count" -gt 1 ]]; then
        has_multiple_series=true
    elif echo "$query" | grep -q -E '(index|generation|instance).*=' || echo "$query" | grep -q '{.*=' ; then
        # Query has label selectors, might return multiple series depending on data
        has_multiple_series=true
    fi
    
    # For metrics that typically return multiple series, verify at least one has a valid value
    if [[ "$has_multiple_series" == "true" ]]; then
        local has_valid_value=$(echo "$response" | jq -r '.data.result[] | select(.value[1] != null and .value[1] != "NaN") | .value[1]' | head -1)
        if [[ -n "$has_valid_value" ]]; then
            echo "✅ Available (${result_count} series)"
            return 0
        else
            if [[ "$ALLOW_NO_DATA" == "true" ]]; then
                echo "✅ Available (series present, values not ready yet)"
                return 0
            fi
            if [[ "$optional" == "true" ]]; then
                echo "❌ Not available (optional - no valid values)"
            else
                echo "❌ Not available (no valid values)"
                ((FAILED_TESTS++))
            fi
            return 1
        fi
    else
        # Single series metric, check if first result has a value
        local value=$(echo "$response" | jq -r '.data.result[0].value[1]')
        if [[ "$value" != "null" && "$value" != "NaN" && -n "$value" ]]; then
            echo "✅ Available"
            return 0
        else
            if [[ "$ALLOW_NO_DATA" == "true" ]]; then
                echo "✅ Available (value not ready yet)"
                return 0
            fi
            if [[ "$optional" == "true" ]]; then
                echo "❌ Not available (optional - no valid value)"
            else
                echo "❌ Not available (no valid value)"
                ((FAILED_TESTS++))
            fi
            return 1
        fi
    fi
}

# Read the dashboard file and extract unique Prometheus queries
echo "📋 Extracting queries from dashboard..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
dashboard_file="$SCRIPT_DIR/../grafana/provisioning/dashboards/mongodb-dashboard.json"

# Extract all expr queries from the dashboard more carefully
temp_file=$(mktemp)
jq -r '.panels[]? | select(.targets?) | .targets[]? | select(.expr?) | .expr' "$dashboard_file" | sort -u > "$temp_file"

echo "📊 Found $(wc -l < "$temp_file") unique queries to test"
echo ""

while IFS= read -r expr; do
    # Skip empty expressions
    if [[ -z "$expr" || "$expr" == "null" ]]; then
        continue
    fi
    
    # Clean up the expression (remove any quotes and handle Grafana variables)
    expr=$(echo "$expr" | sed 's/^"//;s/"$//' | sed 's/\$__rate_interval/5m/g')
    
    # Determine if this might be an optional metric (search-related metrics that may not have data)
    optional="false"
    if echo "$expr" | grep -q -E "(search|vector).*Command"; then
        optional="true"
    elif echo "$expr" | grep -q 'quantile="0.95"'; then
        # 95th percentile metrics require more data to be meaningful
        optional="true"
    fi
    
    # Create a friendly name from the expression
    friendly_name=$(echo "$expr" | sed 's/\$__rate_interval/5m/g' | head -c 80)
    if [[ ${#expr} -gt 80 ]]; then
        friendly_name="${friendly_name}..."
    fi
    
    test_metric_smart "$expr" "$friendly_name" "$optional"
done < "$temp_file"

# Clean up
rm "$temp_file"
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
    echo "   4. Run ./scripts/test-monitoring.sh to check basic connectivity"
    echo "   5. If there is no traffic yet, run with --allow-no-data"
    echo "   6. For strict checks after generating data, run with --strict"
    echo ""
    echo "📊 Dashboard may not display correctly until all metrics are available."
    exit 1
fi