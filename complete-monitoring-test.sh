#!/bin/bash

# Complete MongoDB Prometheus Monitoring Test & Setup Guide

echo "🚀 MongoDB Community Search - Complete Monitoring Test"
echo "====================================================="

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    case $status in
        "success") echo -e "${GREEN}✅ $message${NC}" ;;
        "error") echo -e "${RED}❌ $message${NC}" ;;
        "warning") echo -e "${YELLOW}⚠️  $message${NC}" ;;
        "info") echo -e "${BLUE}ℹ️  $message${NC}" ;;
    esac
}

# Check if services are running
print_status "info" "Checking service status..."
if ! docker compose ps | grep -q "Up"; then
    print_status "error" "Services are not running. Start them with: ./start-monitoring.sh"
    exit 1
fi

# Test basic connectivity
print_status "info" "Testing basic connectivity..."

services=("localhost:9090" "localhost:3000" "localhost:9216" "localhost:9946")
service_names=("Prometheus" "Grafana" "MongoDB Exporter" "Mongot Metrics")

for i in "${!services[@]}"; do
    if curl -s --max-time 5 "${services[$i]}" > /dev/null 2>&1; then
        print_status "success" "${service_names[$i]} is accessible"
    else
        print_status "error" "${service_names[$i]} is not accessible"
    fi
done

echo ""
print_status "info" "Testing Prometheus metrics collection..."

# Test MongoDB metrics
mongodb_metrics=$(curl -s "http://localhost:9090/api/v1/label/__name__/values" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    mongodb_metrics = [m for m in data['data'] if 'mongodb' in m.lower()]
    print(len(mongodb_metrics))
except:
    print(0)
")

if [ "$mongodb_metrics" -gt 100 ]; then
    print_status "success" "MongoDB metrics collection working ($mongodb_metrics metrics available)"
else
    print_status "warning" "Limited MongoDB metrics ($mongodb_metrics metrics). Check exporter configuration."
fi

# Test specific important metrics
echo ""
print_status "info" "Testing key MongoDB metrics..."

key_metrics=("mongodb_up" "mongodb_ss_connections" "mongodb_ss_opcounters" "mongodb_ss_mem")
key_descriptions=("MongoDB Status" "Connections" "Operation Counters" "Memory Usage")

for i in "${!key_metrics[@]}"; do
    result=$(curl -s "http://localhost:9090/api/v1/query?query=${key_metrics[$i]}" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data['status'] == 'success' and data['data']['result']:
        print('found')
    else:
        print('missing')
except:
    print('error')
")
    
    case $result in
        "found") print_status "success" "${key_descriptions[$i]} metrics available" ;;
        "missing") print_status "warning" "${key_descriptions[$i]} metrics not found" ;;
        "error") print_status "error" "${key_descriptions[$i]} metrics query failed" ;;
    esac
done

echo ""
print_status "info" "=== ACCESS POINTS ==="
echo ""
echo "🔍 Prometheus Web UI:"
echo "   URL: http://localhost:9090"
echo "   Try these queries:"
echo "     - mongodb_up"
echo "     - mongodb_ss_connections{conn_type=\"current\"}"
echo "     - rate(mongodb_ss_opcounters[5m])"
echo ""

echo "📊 Grafana Dashboard:"
echo "   URL: http://localhost:3000"
echo "   Login: admin/admin"
echo "   Pre-configured dashboard: 'MongoDB Community Search Monitoring'"
echo ""

echo "📈 Direct Metrics Endpoints:"
echo "   MongoDB Exporter: http://localhost:9216/metrics"
echo "   Mongot Metrics: http://localhost:9946/metrics"
echo ""

print_status "info" "=== QUICK TESTS ==="
echo ""

echo "1️⃣  Test Prometheus Queries (copy & paste in Prometheus UI):"
echo ""
echo "   # Check MongoDB status"
echo "   mongodb_up"
echo ""
echo "   # Current connections"  
echo "   mongodb_ss_connections{conn_type=\"current\"}"
echo ""
echo "   # Operations per second"
echo "   rate(mongodb_ss_opcounters[5m])"
echo ""
echo "   # Memory usage"
echo "   mongodb_ss_mem"
echo ""
echo "   # All MongoDB metrics"
echo "   {__name__=~\"mongodb_.*\"}"
echo ""

echo "2️⃣  Test Grafana Dashboard:"
echo "   - Open http://localhost:3000"
echo "   - Login with admin/admin"
echo "   - Look for 'MongoDB Community Search Monitoring' dashboard"
echo "   - Or go to Dashboards > Import and use ID: 2583"
echo ""

echo "3️⃣  Command Line Tests:"
echo ""
echo "   # Get MongoDB status"
echo "   curl -s \"http://localhost:9090/api/v1/query?query=mongodb_up\" | python3 -m json.tool"
echo ""
echo "   # Count all metrics"
echo "   curl -s http://localhost:9216/metrics | grep \"^mongodb_\" | wc -l"
echo ""
echo "   # View raw metrics"  
echo "   curl -s http://localhost:9216/metrics | grep \"mongodb_up\""
echo ""

print_status "info" "=== TROUBLESHOOTING ==="
echo ""
echo "If you see issues:"
echo ""
echo "🔧 Check service logs:"
echo "   docker compose logs prometheus"
echo "   docker compose logs mongodb-exporter"
echo "   docker compose logs grafana"
echo ""
echo "🔧 Restart services:"
echo "   docker compose restart prometheus mongodb-exporter grafana"
echo ""
echo "🔧 Check targets in Prometheus:"
echo "   curl http://localhost:9090/api/v1/targets"
echo ""

print_status "success" "Monitoring setup test completed!"
print_status "info" "Check the output above and follow the access points to explore your metrics."