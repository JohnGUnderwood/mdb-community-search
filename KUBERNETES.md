# Kubernetes Deployment - Quick Start

## Prerequisites

- Kubernetes cluster (v1.24+)
- `kubectl` configured and connected to your cluster
- MongoDB Controllers for Kubernetes (MCK) installed (see below)
- A kubectl context to connect to
```bash
# List contexts
kubectl config get-contexts

# Select context to use. E.g. local docker deployment
kubectl config use-context docker-desktop
```

## Install MongoDB Controllers for Kubernetes (MCK)

```bash
# Add MongoDB Helm repo
helm repo add mongodb https://mongodb.github.io/helm-charts
helm repo update

# Install MCK operator (v1.7.0)
helm install mongodb-kubernetes mongodb/mongodb-kubernetes \
  --version 1.7.0 \
  --namespace mongodb \
  --create-namespace
```

## Quick Start Deployment

### Automated Helper Scripts (closest to Docker Compose flow)

```bash
chmod +x start-monitoring-k8s.sh test-monitoring.sh stop-monitoring-k8s.sh

# Apply manifests, wait for core resources, and run monitoring checks
./start-monitoring-k8s.sh

# Run shared monitoring checks (start-monitoring-k8s.sh handles port-forwards)
./test-monitoring.sh

# Stop local monitoring port-forwards
./stop-monitoring-k8s.sh

# Optional cleanup modes
./stop-monitoring-k8s.sh --delete-resources
./stop-monitoring-k8s.sh --delete-namespace
```

Environment overrides:
- `K8S_NAMESPACE` (default: `mongodb`)
- `ADMIN_PASSWORD` (default: `admin`, used for display/connection hints)
- `GRAFANA_PASSWORD` (default: `admin`, used for display)

Port-forward note:
- `./start-monitoring-k8s.sh` opens local port-forwards for Search health (`8080`), Search metrics (`9946`), MongoDB exporter (`9216`), Prometheus (`9090`), and Grafana (`3000`).
- These forwards stay running after setup so `./test-monitoring.sh` can be run separately.
- Stop them with `./stop-monitoring-k8s.sh`.
- To make startup behave as one-shot cleanup on exit, run with `KEEP_PORT_FORWARDS=false ./start-monitoring-k8s.sh`.

### Option 1: One-command defaults (recommended)

```bash
# Deploy namespace, secrets, MongoDBCommunity, MongoDBSearch, monitoring,
# and Grafana provisioning
kubectl apply -k .

# Wait for MongoDBCommunity CR to become Running
kubectl wait -n mongodb \
  --for=jsonpath='{.status.phase}'=Running \
  mdbc/mongodb --timeout=600s

# Wait for MongoDBSearch CR to become Running
kubectl wait -n mongodb \
  --for=jsonpath='{.status.phase}'=Running \
  mdbs/mongodb --timeout=600s

# Show core resources
kubectl get mdbc,mdbs,pods -n mongodb

# Generate metrics in k8s mode (runs mongosh in-pod)
K8S_NAMESPACE=mongodb ./scripts/generate-metrics.sh k8s
```

### Option 2: With Custom Passwords

```bash
# Create namespace first
kubectl create namespace mongodb

# Create secrets with custom passwords (will override defaults)
kubectl create secret generic admin-user-password \
  --from-literal=password=YOUR_ADMIN_PASSWORD \
  -n mongodb

kubectl create secret generic mdb-user-password \
  --from-literal=password=YOUR_APP_USER_PASSWORD \
  -n mongodb

kubectl create secret generic mongodb-search-sync-source-password \
  --from-literal=password=YOUR_SEARCH_SYNC_PASSWORD \
  -n mongodb

# Deploy everything
kubectl apply -k .
```

## Verify Deployment

```bash
# Show CR and pod state
kubectl get mdbc,mdbs,pods -n mongodb

# Inspect operator-managed status
kubectl describe mdbc mongodb -n mongodb
kubectl describe mdbs mongodb -n mongodb

# Verify MongoDB from inside the pod (no local mongosh required)
kubectl exec -i -n mongodb mongodb-0 -c mongod -- \
  mongosh -u admin -p "${ADMIN_PASSWORD:-admin}" --authenticationDatabase admin --eval "db.adminCommand('ping')"
```

## Optional: Restore Sample Data

To load full MongoDB sample datasets, use the restore Job below:

### Using sampledata.archive

1. Download the archive (one-time, ~50MB) to the repository root:
```bash
cd /Users/junderwood/GitHub/mdb-community-search
curl https://atlas-education.s3.amazonaws.com/sampledata.archive -o sampledata.archive
```

2. Update `kubernetes/05-restore-sample-data-job.yml` to bind-mount the archive from your repository root.

Find the `volumes` section (at the bottom) and replace `emptyDir: {}` with:
```yaml
volumes:
  - name: sample-archive
    hostPath:
      path: /Users/junderwood/GitHub/mdb-community-search
      type: Directory
```
(Replace the path with your actual repository root directory)

3. Run the restore Job:
```bash
kubectl apply -f kubernetes/05-restore-sample-data-job.yml
kubectl logs -n mongodb job/mongodb-restore-sample-data -f
```

The Job will:
- Look for `sampledata.archive` in the mounted `/mnt/sample-data` directory
- Skip gracefully if the archive is not found (not an error—metrics Job data already works)
- Check if sample data already exists and skip restore if present
- Restore all sample databases when the archive is available

To re-run after deletion:
```bash
kubectl delete job -n mongodb mongodb-restore-sample-data
kubectl apply -f kubernetes/05-restore-sample-data-job.yml
```

## Access Services

### MongoDB (optional local access)
```bash
kubectl port-forward -n mongodb svc/mongodb-svc 27017:27017
# Connection string: mongodb://admin:admin@localhost:27017/admin?authSource=admin
```

For helper scripts in `k8s` mode, MongoDB port-forward is not required because they execute `mongosh`/`mongorestore` inside the pod. The sample-data loader uploads `sampledata.archive` into the `mongod` container first, then runs `mongorestore` using that in-pod file.

Load sample data with the Kubernetes helper script:
```bash
K8S_NAMESPACE=mongodb ./scripts/load-sample-data-k8s.sh
```

### Prometheus
```bash
kubectl port-forward -n mongodb svc/prometheus 9090:9090
# Open http://localhost:9090
```

### Grafana
```bash
kubectl port-forward -n mongodb svc/grafana 3000:3000
# Open http://localhost:3000
# Default credentials: admin/admin
# Dashboard is auto-provisioned: MongoDB Community Search Monitoring
```

## Sample Data

### Automatic Seed Data
The local metrics script `scripts/generate-metrics.sh` will create search indexes and run sample queries against `sample_mflix` to populate dashboard metrics.

### Optional: Restore Full Sample Datasets

To restore the complete MongoDB sample datasets (sample_airbnb, sample_mflix, etc.), see [Optional: Restore Sample Data](#optional-restore-sample-data) above.

## Re-run Metric Generation (Optional)

Run metrics generation using the shared script with the `k8s` runtime argument.

```bash
K8S_NAMESPACE=mongodb ./scripts/generate-metrics.sh k8s
```

## Cleanup

```bash
# Delete all resources
kubectl delete namespace mongodb
```
