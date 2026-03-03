# MongoDB Community with Search and Monitoring

A complete MongoDB Community Server and MongoDB Community Search (mongot) setup with optional Prometheus and Grafana monitoring. Supports both Docker Compose for local development and Kubernetes for cluster deployments.

## Features

- **MongoDB Community Server** with replica set configuration and authentication
- **MongoDB Community Search (mongot)** for Atlas Search capabilities
- **Prometheus + Grafana** monitoring with pre-built dashboards
- **Auto-embedding** support via Voyage AI (optional)
- **Sample data** loading with search indexes and test queries
- Helper scripts for setup, monitoring, metrics generation, and testing

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) (for Docker Compose deployment)
- [kubectl](https://kubernetes.io/docs/tasks/tools/) + a Kubernetes cluster (for Kubernetes deployment)
- Sample data archive (optional, but recommended):
  ```bash
  curl https://atlas-education.s3.amazonaws.com/sampledata.archive -o sampledata.archive
  ```

## Quick Start

### Docker Compose

```bash
cd docker

# Generate security files and start services
export ADMIN_PASSWORD="admin" MONGOT_PASSWORD="mongotPassword"
docker compose --profile setup run --rm setup-generator
docker network create search-community
docker compose up mongod mongot -d
```

To start with full monitoring (Prometheus + Grafana):
```bash
./docker/start-monitoring.sh
```

See [docker/README.md](docker/README.md) for detailed setup options, auto-embedding configuration, custom passwords, and troubleshooting.

### Kubernetes

```bash
cd kubernetes

# Deploy all resources (requires MongoDB Controllers for Kubernetes)
kubectl apply -k .

# Or use the helper script for full setup with monitoring
./start-monitoring-k8s.sh
```

See [kubernetes/README.md](kubernetes/README.md) for MCK installation, custom passwords, sample data restore, and detailed instructions.

## Project Structure

```
├── docker/                  # Docker Compose deployment
│   ├── docker-compose.yml   # Service definitions
│   ├── mongod.conf          # MongoDB server configuration
│   ├── mongot.conf          # MongoDB Search configuration
│   ├── init-mongo.sh        # Initialization script
│   ├── prometheus.yml       # Prometheus scrape configuration
│   └── start-monitoring.sh  # Full stack startup with monitoring
├── kubernetes/              # Kubernetes deployment
│   ├── 00-namespace.yml     # Namespace definition
│   ├── 01-secrets.yml       # Secrets for authentication
│   ├── 02-mongodb-community.yml  # MongoDBCommunity CR
│   ├── 03-mongot-deployment.yml  # MongoDBSearch CR
│   ├── 04-monitoring.yml    # Prometheus, Grafana, exporter
│   ├── kustomization.yaml   # Kustomize overlay
│   ├── start-monitoring-k8s.sh   # Full K8s setup with monitoring
│   ├── stop-monitoring-k8s.sh    # Cleanup port-forwards and resources
│   └── load-sample-data-k8s.sh   # Sample data loader
├── grafana/                 # Grafana provisioning
│   └── provisioning/        # Dashboards and datasources
├── scripts/                 # Shared helper scripts
│   ├── generate-metrics.sh  # Generate test search activity
│   ├── test-monitoring.sh   # Validate monitoring endpoints
│   └── test-dashboard-metrics.sh  # Validate Grafana metrics
└── sampledata.archive       # MongoDB sample datasets (downloaded)
```

## Access Points

| Service | URL | Default Credentials |
|---------|-----|-------------------|
| MongoDB | `mongodb://admin:admin@localhost:27017` | admin / admin |
| mongot Health | http://localhost:8080/health | — |
| mongot Metrics | http://localhost:9946/metrics | — |
| Prometheus | http://localhost:9090 | — |
| Grafana | http://localhost:3000 | admin / admin |
| MongoDB Exporter | http://localhost:9216/metrics | — |

## Helper Scripts

| Script | Description |
|--------|-------------|
| `docker/start-monitoring.sh` | Start Docker Compose stack with monitoring |
| `kubernetes/start-monitoring-k8s.sh` | Deploy K8s resources, set up port-forwards, run tests |
| `kubernetes/stop-monitoring-k8s.sh` | Stop port-forwards, optionally delete resources |
| `kubernetes/load-sample-data-k8s.sh` | Load sample data into K8s MongoDB pod |
| `scripts/generate-metrics.sh [compose\|k8s]` | Create search indexes and run queries for metrics |
| `scripts/test-monitoring.sh` | Validate all monitoring endpoints |
| `scripts/test-dashboard-metrics.sh` | Validate Grafana dashboard metric queries |