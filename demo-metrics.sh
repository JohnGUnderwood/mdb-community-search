#!/bin/bash

# Demonstrate Prometheus metrics queries for MongoDB monitoring

echo "🔍 MongoDB Community Search - Prometheus Metrics Demo"
echo "======================================================"

# Function to run a Prometheus query
query_prometheus() {
    local query="$1"
    local description="$2"
    
    echo ""
    echo "📊 $description"
    echo "Query: $query"
    echo "Result:"
    
    result=$(curl -s "http://localhost:9090/api/v1/query?query=$(echo "$query" | sed 's/ /%20/g')" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data['status'] == 'success' and data['data']['result']:
        for item in data['data']['result']:
            metric = item['metric']
            value = item['value'][1]
            labels = ', '.join([f'{k}={v}' for k, v in metric.items() if k != '__name__'])
            print(f'  {metric.get(\"__name__\", \"unknown\")}{{{labels}}} = {value}')
    else:
        print('  No data available')
except Exception as e:
    print(f'  Error parsing response: {e}')
")
    
    if [ -z "$result" ]; then
        echo "  ❌ Query failed or no results"
    else
        echo "$result"
    fi
}

echo ""
echo "Testing basic connectivity..."
if ! curl -s http://localhost:9090 > /dev/null; then
    echo "❌ Prometheus is not accessible at http://localhost:9090"
    echo "   Run: ./start-monitoring.sh"
    exit 1
fi

echo "✅ Prometheus is running"

# Test queries
query_prometheus "mongodb_up" "MongoDB Server Status"
query_prometheus "mongodb_connections" "MongoDB Connections"  
query_prometheus "up" "All Targets Status"
query_prometheus "prometheus_tsdb_symbol_table_size_bytes" "Prometheus Internal Metrics"

# Count available metrics
echo ""
echo "📈 Available Metrics Summary"
echo "----------------------------"

total_metrics=$(curl -s "http://localhost:9090/api/v1/label/__name__/values" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    metrics = data['data']
    mongodb_metrics = [m for m in metrics if 'mongodb' in m]
    mongot_metrics = [m for m in metrics if 'mongot' in m]
    prometheus_metrics = [m for m in metrics if 'prometheus' in m]
    
    print(f'Total metrics: {len(metrics)}')
    print(f'MongoDB metrics: {len(mongodb_metrics)}')
    print(f'Mongot metrics: {len(mongot_metrics)}')
    print(f'Prometheus metrics: {len(prometheus_metrics)}')
    print(f'Other metrics: {len(metrics) - len(mongodb_metrics) - len(mongot_metrics) - len(prometheus_metrics)}')
    
    if mongodb_metrics:
        print(f'\\nMongoDB metrics available:')
        for metric in sorted(mongodb_metrics)[:5]:
            print(f'  - {metric}')
        if len(mongodb_metrics) > 5:
            print(f'  ... and {len(mongodb_metrics) - 5} more')
            
except Exception as e:
    print(f'Error: {e}')
")

echo "$total_metrics"

echo ""
echo "🎯 Next Steps:"
echo "  1. Open Prometheus: http://localhost:9090"
echo "  2. Open Grafana: http://localhost:3000 (admin/admin)"  
echo "  3. See PROMETHEUS-GUIDE.md for detailed instructions"
echo ""