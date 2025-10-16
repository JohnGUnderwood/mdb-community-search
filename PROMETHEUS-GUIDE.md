# Testing and Using Prometheus Metrics

## 🔍 Testing Metrics Collection

### 1. Check Prometheus Targets
Visit http://localhost:9090/targets to see if all targets are being scraped:
- **mongodb-exporter**: Should show "UP" status
- **mongot**: Should show "UP" status  
- **prometheus**: Should show "UP" status

### 2. Query Available Metrics

In the Prometheus web UI (http://localhost:9090), try these queries:

#### MongoDB Community Server Metrics
```promql
# Check if MongoDB is up
mongodb_up

# MongoDB connections (current, active, available)
mongodb_ss_connections{conn_type="current"}
mongodb_ss_connections{conn_type="active"}
mongodb_ss_connections{conn_type="available"}

# MongoDB operations per second  
rate(mongodb_ss_opcounters{legacy_op_type="insert"}[5m])
rate(mongodb_ss_opcounters{legacy_op_type="query"}[5m])
rate(mongodb_ss_opcounters{legacy_op_type="update"}[5m])
rate(mongodb_ss_opcounters{legacy_op_type="delete"}[5m])

# MongoDB memory usage (in MB)
mongodb_ss_mem_resident
mongodb_ss_mem_virtual

# List all MongoDB metrics
{__name__=~"mongodb_.*"}
```

#### System Metrics
```promql
# Prometheus itself
prometheus_tsdb_symbol_table_size_bytes

# Process metrics
process_cpu_seconds_total
```

#### Mongot Metrics (when working)
```promql
# List all mongot metrics
{__name__=~"mongot_.*"}
```

### 3. Command Line Testing
```bash
# Test MongoDB exporter metrics directly
curl http://localhost:9216/metrics | grep mongodb_up

# Test mongot metrics directly  
curl http://localhost:9946/metrics | head -20

# Query Prometheus API for MongoDB status
curl -s "http://localhost:9090/api/v1/query?query=mongodb_up" | python3 -m json.tool

# Get all available metric names
curl -s "http://localhost:9090/api/v1/label/__name__/values" | python3 -m json.tool
```

## 📊 Setting Up Grafana Dashboards

### 1. Access Grafana
- URL: http://localhost:3000
- Username: admin  
- Password: admin (or your GRAFANA_PASSWORD)

### 2. Create Custom Dashboard for MongoDB

#### Step-by-step:
1. Click **+** → **Dashboard**
2. Click **Add visualization**
3. Select **Prometheus** as data source
4. Add these panels:

**Panel 1: MongoDB Status**
```promql
mongodb_up
```
- Visualization: Stat
- Title: "MongoDB Status"

**Panel 2: Connections**
```promql  
mongodb_ss_connections{conn_type="current"}
mongodb_ss_connections{conn_type="active"}
```
- Visualization: Time series
- Title: "MongoDB Connections"

**Panel 3: Operations Rate**
```promql
rate(mongodb_ss_opcounters{legacy_op_type="insert"}[5m])
rate(mongodb_ss_opcounters{legacy_op_type="query"}[5m])
rate(mongodb_ss_opcounters{legacy_op_type="update"}[5m])
rate(mongodb_ss_opcounters{legacy_op_type="delete"}[5m])
```
- Visualization: Time series  
- Title: "Operations per Second"

**Panel 4: Memory Usage**
```promql
mongodb_ss_mem_resident * 1024 * 1024
mongodb_ss_mem_virtual * 1024 * 1024
```
- Visualization: Time series
- Title: "Memory Usage (bytes)"

### 4. Additional Dashboard Resources

#### MongoDB Dashboards from Grafana.com:
- **2583**: MongoDB Overview
- **7353**: MongoDB Exporter Dashboard
- **12079**: MongoDB Instance Summary

#### Import process:
1. Go to https://grafana.com/grafana/dashboards/
2. Search for "MongoDB"
3. Copy the dashboard ID
4. In Grafana: **+** → **Import** → paste ID → **Load**

## 🚨 Troubleshooting

### MongoDB Exporter Issues
```bash
# Check exporter logs
docker compose logs mongodb-exporter

# Test exporter endpoint
curl http://localhost:9216/metrics | grep mongodb_up
```

### Mongot Metrics Issues  
```bash
# Check mongot logs
docker compose logs mongot

# Test mongot endpoint
curl http://localhost:9946/metrics | head -10

# Check if mongot is healthy
curl http://localhost:8080
```

### Prometheus Issues
```bash
# Check Prometheus logs
docker compose logs prometheus

# Check Prometheus config
curl http://localhost:9090/api/v1/status/config

# Check targets status
curl http://localhost:9090/api/v1/targets
```

## 💡 Useful PromQL Queries

### MongoDB Performance
```promql
# Connection utilization percentage
mongodb_ss_connections{conn_type="current"} / mongodb_ss_connections{conn_type="available"} * 100

# Operation rate by type
sum by (legacy_op_type) (rate(mongodb_ss_opcounters[5m]))

# Memory usage in bytes
mongodb_ss_mem_resident * 1024 * 1024
mongodb_ss_mem_virtual * 1024 * 1024

# WiredTiger cache usage
mongodb_ss_wt_cache_bytes_currently_in_the_cache
mongodb_ss_wt_cache_maximum_bytes_configured

# Network I/O
rate(mongodb_ss_network_bytesIn[5m])
rate(mongodb_ss_network_bytesOut[5m])
```

### Alerting Examples
```promql
# MongoDB down
mongodb_up == 0

# High connection usage (>80%)
mongodb_ss_connections{conn_type="current"} / mongodb_ss_connections{conn_type="available"} > 0.8

# High memory usage (>1GB resident memory)
mongodb_ss_mem_resident > 1024

# Search command failures
rate(mongot_command_searchBetaCommandFailure_total[5m]) > 0

# High search latency (>1 second average)
rate(mongot_command_searchBetaCommandTotalLatency_seconds_sum[5m]) / rate(mongot_command_searchBetaCommandTotalLatency_seconds_count[5m]) > 1
```

## 🎯 Next Steps

1. **Import MongoDB dashboards** from Grafana.com
2. **Create alerts** for critical metrics  
3. **Set up notification channels** (Slack, email, etc.)
4. **Monitor mongot metrics** once scraping is fixed
5. **Create custom dashboards** for your specific use cases