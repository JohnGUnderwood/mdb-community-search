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

### Option 1: One-command defaults (recommended)

```bash
# Deploy namespace, secrets, MongoDBCommunity, MongoDBSearch, monitoring,
# Grafana provisioning, and a one-shot metric generation Job
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

# Watch the metric generation job complete
kubectl logs -n mongodb job/mongodb-generate-metrics -f
```

### Option 2: With Custom Passwords

```bash
# Create namespace first
kubectl create namespace mongodb

# Create secrets with custom passwords (will override defaults)
kubectl create secret generic mdb-admin-user-password \
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

# Check job status (should complete once metrics are generated)
kubectl get jobs -n mongodb

# Inspect operator-managed status
kubectl describe mdbc mongodb -n mongodb
kubectl describe mdbs mongodb -n mongodb

# Port forward to test
kubectl port-forward -n mongodb svc/mongodb-svc 27017:27017
# In another terminal:
mongosh "mongodb://mdb-admin:admin@localhost:27017/admin?authSource=admin"
```

## Optional: Restore Sample Data

The metric generation Job automatically seeds minimal test data so dashboards populate without external data. For full MongoDB sample datasets:

### Using sampledata.archive

1. Download the archive (one-time, ~50MB):
```bash
curl https://atlas-education.s3.amazonaws.com/sampledata.archive -o sampledata.archive
```

2. Create a volume to mount it into the Job. For local clusters (Docker Desktop), use a `hostPath`:
```bash
# Make the file accessible from the cluster
mkdir -p /tmp/mongodb-data
cp sampledata.archive /tmp/mongodb-data/
```

3. Modify `kubernetes/06-restore-sample-data-job.yml` to mount your archive:
```yaml
volumes:
  - name: sample-archive
    hostPath:
      path: /tmp/mongodb-data  # or your actual path
      type: Directory
```

4. Run the restore Job:
```bash
kubectl apply -f kubernetes/06-restore-sample-data-job.yml
kubectl logs -n mongodb job/mongodb-restore-sample-data -f
```

The Job will check if data already exists and skip restore if not needed. Use `kubectl delete job -n mongodb mongodb-restore-sample-data` to re-run.

## Access Services

### MongoDB
```bash
kubectl port-forward -n mongodb svc/mongodb-svc 27017:27017
# Connection string: mongodb://mdb-admin:admin@localhost:27017/admin?authSource=admin
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
The `mongodb-generate-metrics` Job automatically seeds the `sample_mflix.embedded_movies` collection with 4 test documents. This is sufficient to populate dashboard metrics and test search functionality.

### Optional: Restore Full Sample Datasets

To restore the complete MongoDB sample datasets (sample_airbnb, sample_mflix, etc.), see [Optional: Restore Sample Data](#optional-restore-sample-data) above.

## Re-run Metric Generation (Optional)

The `mongodb-generate-metrics` Job runs automatically on deploy and exits after generating traffic.

```bash
kubectl delete job -n mongodb mongodb-generate-metrics
kubectl apply -f kubernetes/05-generate-metrics-job.yml
kubectl logs -n mongodb job/mongodb-generate-metrics -f
```

## Cleanup

```bash
# Delete all resources
kubectl delete namespace mongodb
```
