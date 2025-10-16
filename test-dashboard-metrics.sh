#!/bin/bash

# Test script to validate that all metrics used in the Grafana dashboard are available

echo "🔍 Testing Dashboard Metrics..."
echo "================================"

# Test MongoDB Up metric
echo -n "Testing mongodb_up: "
if curl -s "http://localhost:9090/api/v1/query?query=mongodb_up" | jq -r '.data.result[0].value[1]' >/dev/null 2>&1; then
  echo "✅ Available"
else
  echo "❌ Not available"
fi

# Test MongoDB Connections
echo -n "Testing mongodb_ss_connections: "
if curl -s "http://localhost:9090/api/v1/query?query=mongodb_ss_connections" | jq -r '.data.result' | grep -q "current" 2>/dev/null; then
  echo "✅ Available"
else
  echo "❌ Not available"
fi

# Test MongoDB Operations
echo -n "Testing mongodb_ss_opcounters: "
if curl -s "http://localhost:9090/api/v1/query?query=mongodb_ss_opcounters" | jq -r '.data.result' | grep -q "insert" 2>/dev/null; then
  echo "✅ Available"
else
  echo "❌ Not available"
fi

# Test MongoDB Memory
echo -n "Testing mongodb_ss_mem_resident: "
if curl -s "http://localhost:9090/api/v1/query?query=mongodb_ss_mem_resident" | jq -r '.data.result[0].value[1]' >/dev/null 2>&1; then
  echo "✅ Available"
else
  echo "❌ Not available"
fi

# Test MongoDB Network
echo -n "Testing mongodb_ss_network_bytesIn: "
if curl -s "http://localhost:9090/api/v1/query?query=mongodb_ss_network_bytesIn" | jq -r '.data.result[0].value[1]' >/dev/null 2>&1; then
  echo "✅ Available"
else
  echo "❌ Not available"
fi

# Test Mongot Metrics
echo -n "Testing mongot_command_searchBetaCommandTotalLatency_seconds: "
if curl -s "http://localhost:9090/api/v1/query?query=mongot_command_searchBetaCommandTotalLatency_seconds" | jq -r '.data.result' >/dev/null 2>&1; then
  echo "✅ Available"
else
  echo "❌ Not available (expected if no search queries have been made)"
fi

# Test Mongot Service Status 
echo -n "Testing up{job=\"mongot\"}: "
if curl -s "http://localhost:9090/api/v1/query?query=up{job=\"mongot\"}" | jq -r '.data.result[0].value[1]' >/dev/null 2>&1; then
  echo "✅ Available"
else
  echo "❌ Not available"
fi

# Test Database Stats
echo -n "Testing mongodb_dbstats_collections: "
if curl -s "http://localhost:9090/api/v1/query?query=mongodb_dbstats_collections" | jq -r '.data.result' | grep -q "database" 2>/dev/null; then
  echo "✅ Available"
else
  echo "❌ Not available"
fi

# Test WiredTiger Cache
echo -n "Testing mongodb_ss_wt_cache_bytes_currently_in_the_cache: "
if curl -s "http://localhost:9090/api/v1/query?query=mongodb_ss_wt_cache_bytes_currently_in_the_cache" | jq -r '.data.result[0].value[1]' >/dev/null 2>&1; then
  echo "✅ Available"
else
  echo "❌ Not available"
fi

echo ""
echo "✨ Dashboard metric validation complete!"
echo ""
echo "📊 To test the dashboard, open Grafana at: http://localhost:3000"
echo "   - Username: admin"
echo "   - Password: admin"
echo "   - Dashboard: 'MongoDB Community Search Monitoring'"