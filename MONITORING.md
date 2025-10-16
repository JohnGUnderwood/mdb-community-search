# MongoDB Community Search - Prometheus Monitoring

This setup provides comprehensive monitoring for MongoDB Community Server and Atlas Search (mongot) using Prometheus and Grafana.

## Architecture

- **MongoDB Community Server**: Main database server
- **Mongot**: MongoDB Atlas Search service with native Prometheus metrics
- **MongoDB Exporter**: Collects metrics from MongoDB Community Server for Prometheus
- **Prometheus**: Time-series database for metrics collection
- **Grafana**: Visualization and dashboarding

## Quick Start

### Option 1: Full Stack with Monitoring (Recommended)
```bash
./start-monitoring.sh
```

### Option 2: Manual Docker Compose
```bash
# Create network if it doesn't exist
docker network create search-community

# Set environment variables (optional)
export ADMIN_PASSWORD=your-admin-password
export MONGOT_PASSWORD=your-mongot-password  
export GRAFANA_PASSWORD=your-grafana-password

# Run setup if needed
docker compose --profile setup up setup-generator

# Start all services
docker compose up -d mongod mongot mongodb-exporter prometheus grafana
```

## Access Points

| Service | URL | Credentials |
|---------|-----|-------------|
| MongoDB | `mongodb://admin:admin@localhost:27017` | admin/admin |
| Mongot Health | http://localhost:8080 | - |
| Mongot Metrics | http://localhost:9946/metrics | - |
| MongoDB Exporter | http://localhost:9216/metrics | - |
| Prometheus | http://localhost:9090 | - |
| Grafana | http://localhost:3000 | admin/admin |

## Metrics Available

### MongoDB Community Server Metrics (via exporter)
- `mongodb_up` - MongoDB server availability (1=up, 0=down)
- `mongodb_ss_connections` - Connection statistics by type (current, active, available)
- `mongodb_ss_network_*` - Network I/O metrics (bytesIn, bytesOut)
- `mongodb_ss_opcounters` - Operation counters by type (insert, query, update, delete)
- `mongodb_ss_mem_*` - Memory usage (resident, virtual in MB)
- `mongodb_ss_wt_*` - WiredTiger storage engine metrics (cache, transactions, etc.)
- `mongodb_dbstats_*` - Database statistics (collections, dataSize, indexSize)

### Mongot (Atlas Search) Metrics (native)
- `mongot_command_searchBetaCommandTotalLatency_seconds` - Search command latency metrics
- `mongot_command_indexStatsCommandTotalLatency_seconds` - Index stats command latency
- `mongot_command_*Failure_total` - Command failure counters
- `mongot_*_executor_*` - Executor thread pool metrics
- All metrics have detailed labels for filtering and aggregation

## Using Prometheus

1. Open http://localhost:9090
2. Use the expression browser to query metrics:
   ```promql
   # MongoDB connection count
   mongodb_ss_connections{conn_type="current"}
   
   # Search command latency and rates
   mongot_command_searchBetaCommandTotalLatency_seconds
   rate(mongot_command_searchBetaCommandTotalLatency_seconds_count[5m])
   
   # All mongot metrics
   {__name__=~"mongot_.*"}
   ```

## Using Grafana

1. Open http://localhost:3000
2. Login with admin/admin (or your GRAFANA_PASSWORD)
3. The Prometheus datasource is pre-configured
4. A comprehensive MongoDB Community Search dashboard is automatically loaded

### Pre-built Dashboard: "MongoDB Community Search Monitoring"

The dashboard includes 13 panels covering:

**MongoDB Core Metrics:**
- Service status (MongoDB & Mongot uptime)
- Connection statistics (current, active connections)
- Operations per second (insert, query, update, delete)
- Memory usage (resident & virtual)
- Network I/O rates

**Search-Specific Metrics:**
- Search command latency (searchBeta, indexStats)
- Search command rates and failure rates
- Mongot executor thread metrics
- Average search latency with color-coded thresholds

**Storage & Performance:**
- Database collection counts and sizes
- WiredTiger cache utilization
- Index sizes by database

### Additional Dashboard Options
- MongoDB Overview Dashboard (Grafana ID: 2583)
- MongoDB Exporter Dashboard (Grafana ID: 7353)
- Custom dashboards for specific use cases

## Validating the Setup

Use the provided test scripts to verify everything is working:

```bash
# Test all monitoring endpoints
./test-monitoring.sh

# Validate dashboard metrics are available in Prometheus
./test-dashboard-metrics.sh

# Generate sample database and search activity for dashboard demonstration
./demo-dashboard.sh
```

The dashboard metrics test will check that all metrics used in the Grafana dashboard are properly available from Prometheus. The demo dashboard script will create search indexes and run queries to populate the dashboard with meaningful data.

## Configuration Files

- `prometheus.yml` - Prometheus scraping configuration
- `grafana/provisioning/datasources/prometheus.yml` - Grafana datasource config
- `grafana/provisioning/dashboards/mongodb-dashboard.json` - Pre-built dashboard
- `docker-compose.yml` - Complete service orchestration

## Troubleshooting

### Check Service Health
```bash
docker compose ps
```

### View Logs
```bash
# MongoDB logs
docker compose logs mongod

# Mongot logs  
docker compose logs mongot

# MongoDB Exporter logs
docker compose logs mongodb-exporter

# Prometheus logs
docker compose logs prometheus
```

### Verify Metrics Endpoints
```bash
# Test mongot metrics
curl http://localhost:9946/metrics

# Test MongoDB exporter metrics
curl http://localhost:9216/metrics

# Test Prometheus targets
curl http://localhost:9090/api/v1/targets
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ADMIN_PASSWORD` | admin | MongoDB admin password |
| `MONGOT_PASSWORD` | mongotPassword | MongoDB mongot user password |
| `GRAFANA_PASSWORD` | admin | Grafana admin password |

## Stopping Services

```bash
docker compose down
```

To also remove volumes (will lose Grafana dashboards and Prometheus data):
```bash
docker compose down -v
```