#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="${K8S_NAMESPACE:-mongodb}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"
GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-admin}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-600s}"
KEEP_PORT_FORWARDS="${KEEP_PORT_FORWARDS:-true}"

PORT_FORWARD_PIDS=()

cleanup() {
  if [ "${#PORT_FORWARD_PIDS[@]}" -gt 0 ]; then
    echo ""
    echo "Stopping background port-forwards..."
    for pid in "${PORT_FORWARD_PIDS[@]}"; do
      if kill -0 "$pid" >/dev/null 2>&1; then
        kill "$pid" >/dev/null 2>&1 || true
      fi
    done
  fi
}

handle_interrupt() {
  echo ""
  echo "Interrupted; stopping background port-forwards..."
  cleanup
  exit 130
}

if [[ "$KEEP_PORT_FORWARDS" == "false" ]]; then
  trap cleanup EXIT
else
  trap handle_interrupt INT TERM
fi

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "❌ Required command not found: $command_name"
    exit 1
  fi
}

confirm_kube_context() {
  local current_context
  local current_cluster
  local current_user

  current_context="$(kubectl config current-context 2>/dev/null || true)"
  if [[ -z "$current_context" ]]; then
    echo "❌ No active kubectl context found."
    echo "Set one first with: kubectl config use-context <context-name>"
    exit 1
  fi

  current_cluster="$(kubectl config view -o jsonpath="{.contexts[?(@.name=='$current_context')].context.cluster}" 2>/dev/null || true)"
  current_user="$(kubectl config view -o jsonpath="{.contexts[?(@.name=='$current_context')].context.user}" 2>/dev/null || true)"

  echo ""
  echo "🔎 Kubernetes context check"
  echo "  Context:   $current_context"
  echo "  Cluster:   ${current_cluster:-unknown}"
  echo "  User:      ${current_user:-unknown}"
  echo "  Namespace: $NAMESPACE"
  echo ""

  read -r -p "Proceed with this Kubernetes context? (y/N): " CONTEXT_REPLY
  if [[ ! "$CONTEXT_REPLY" =~ ^[Yy]$ ]]; then
    echo "Aborted by user."
    exit 0
  fi
}

ensure_operator_ready() {
  echo "Checking MongoDB Kubernetes Operator availability..."

  local operator_deployments
  operator_deployments="$(kubectl get deployment -A -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' | grep 'mongodb-kubernetes-operator' || true)"

  if [[ -z "$operator_deployments" ]]; then
    echo "❌ MongoDB Kubernetes Operator deployment not found."
    echo "Install it first, for example:"
    echo "  helm repo add mongodb https://mongodb.github.io/helm-charts"
    echo "  helm repo update"
    echo "  helm install mongodb-kubernetes mongodb/mongodb-kubernetes --version 1.7.0 --namespace mongodb --create-namespace"
    exit 1
  fi

  while IFS=' ' read -r op_namespace op_name; do
    if [[ -n "$op_namespace" && -n "$op_name" ]]; then
      echo "Waiting for operator deployment/$op_name in namespace $op_namespace..."
      kubectl rollout status -n "$op_namespace" "deployment/$op_name" --timeout=180s
    fi
  done <<< "$operator_deployments"
}

wait_for_cr_running() {
  local resource="$1"
  local label="$2"

  echo "Waiting for $label to be Running..."
  if ! kubectl wait -n "$NAMESPACE" --for=jsonpath='{.status.phase}'=Running "$resource" --timeout="$WAIT_TIMEOUT"; then
    echo "❌ Timed out waiting for $label to become Running."
    echo "Current CR status:"
    kubectl get -n "$NAMESPACE" "$resource" -o yaml | sed -n '1,220p' || true
    echo ""
    echo "Recent namespace events:"
    kubectl get events -n "$NAMESPACE" --sort-by=.lastTimestamp | tail -n 20 || true
    exit 1
  fi
}

wait_for_http() {
  local url="$1"
  local timeout_seconds="${2:-60}"

  for _ in $(seq 1 "$timeout_seconds"); do
    if curl -s -f "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  return 1
}

wait_for_prometheus_job_up() {
  local job_name="$1"
  local timeout_seconds="${2:-120}"

  for _ in $(seq 1 "$timeout_seconds"); do
    if curl -s -G "http://localhost:9090/api/v1/query" --data-urlencode "query=up{job=\"$job_name\"}" \
      | jq -e '.status == "success" and (.data.result | length > 0) and ([.data.result[].value[1] | tonumber] | any(. >= 1))' >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  return 1
}

ensure_endpoint() {
  local url="$1"
  local name="$2"
  local resource="$3"
  local local_port="$4"
  local target_port="$5"

  if curl -s -f "$url" >/dev/null 2>&1; then
    echo "✅ $name already reachable at $url"
    return 0
  fi

  local log_file
  log_file="$(mktemp)"

  echo "ℹ️  Starting port-forward for $name ($resource $local_port:$target_port)..."
  kubectl port-forward -n "$NAMESPACE" "$resource" "$local_port:$target_port" >"$log_file" 2>&1 &
  local pf_pid=$!
  PORT_FORWARD_PIDS+=("$pf_pid")

  if wait_for_http "$url" 60; then
    echo "✅ $name reachable at $url"
    return 0
  fi

  echo "❌ Failed to expose $name at $url"
  echo "Port-forward logs:"
  cat "$log_file"
  exit 1
}


echo "Starting MongoDB Community Search on Kubernetes with monitoring..."

echo "Using namespace: $NAMESPACE"
echo "Using passwords:"
echo "  MongoDB Admin: [HIDDEN]"
echo "  Grafana Admin: [HIDDEN]"

require_command kubectl
require_command curl
require_command jq

confirm_kube_context

if [ ! -f "kustomization.yaml" ]; then
  echo "❌ Run this script from the repository root (kustomization.yaml not found)."
  exit 1
fi

echo ""
echo "Applying Kubernetes manifests..."
kubectl apply -k .

echo ""
ensure_operator_ready

echo ""
wait_for_cr_running "mdbc/mongodb" "MongoDB Community resource"
wait_for_cr_running "mdbs/mongodb" "MongoDB Search resource"

echo "Waiting for core monitoring deployments..."
kubectl rollout status -n "$NAMESPACE" deployment/mongodb-exporter --timeout="$WAIT_TIMEOUT"
kubectl rollout status -n "$NAMESPACE" deployment/prometheus --timeout="$WAIT_TIMEOUT"
kubectl rollout status -n "$NAMESPACE" deployment/grafana --timeout="$WAIT_TIMEOUT"

echo "Reloading Prometheus to ensure latest scrape configuration is active..."
kubectl rollout restart -n "$NAMESPACE" deployment/prometheus
kubectl rollout status -n "$NAMESPACE" deployment/prometheus --timeout="$WAIT_TIMEOUT"

echo ""
echo "Preparing local access to endpoints..."
ensure_endpoint "http://localhost:8080/health" "MongoDB Search Health" "svc/mongodb-search-svc" 8080 8080
ensure_endpoint "http://localhost:9946/metrics" "MongoDB Search Metrics" "svc/mongodb-search-svc" 9946 9946
ensure_endpoint "http://localhost:9216/metrics" "MongoDB Exporter Metrics" "svc/mongodb-exporter" 9216 9216
ensure_endpoint "http://localhost:9090" "Prometheus" "svc/prometheus" 9090 9090
ensure_endpoint "http://localhost:3000" "Grafana" "svc/grafana" 3000 3000

echo ""
echo "Waiting for Prometheus scrape targets to report UP..."
if ! wait_for_prometheus_job_up "mongot" 120; then
  echo "❌ Prometheus target 'mongot' did not become UP in time."
  exit 1
fi
if ! wait_for_prometheus_job_up "mongodb-exporter" 120; then
  echo "❌ Prometheus target 'mongodb-exporter' did not become UP in time."
  exit 1
fi
echo "✅ Prometheus scrape targets are UP"

echo ""
echo "Services available at:"
echo "  MongoDB Search:     http://localhost:8080/health"
echo "  MongoDB Search Met: http://localhost:9946/metrics"
echo "  MongoDB Metrics:    http://localhost:9216/metrics"
echo "  Prometheus:         http://localhost:9090"
echo "  Grafana:            http://localhost:3000 (admin/${GRAFANA_PASSWORD})"


# emoji for loading data
echo "📦 Loading sample data into MongoDB..."
  if [ -x "./scripts/load-sample-data-k8s.sh" ]; then
    K8S_NAMESPACE="$NAMESPACE" ADMIN_PASSWORD="$ADMIN_PASSWORD" ./scripts/load-sample-data-k8s.sh
  else
    echo "⚠️  scripts/load-sample-data-k8s.sh not found or not executable"
    echo "   Run 'chmod +x scripts/load-sample-data-k8s.sh'"
    exit 1
  fi

echo ""
echo "🧪 Running Kubernetes monitoring tests..."
if [ -x "./test-monitoring.sh" ]; then
  ./test-monitoring.sh
else
  echo "⚠️  test-monitoring.sh not found or not executable"
  echo "   Run 'chmod +x test-monitoring.sh'"
fi

echo ""
echo "🧪 Running dashboard metrics test (no-data mode)..."
if [ -x "./scripts/test-dashboard-metrics.sh" ]; then
  (
    cd scripts
    ./test-dashboard-metrics.sh
  )
else
  echo "⚠️  scripts/test-dashboard-metrics.sh not found or not executable"
  echo "   Run 'chmod +x scripts/test-dashboard-metrics.sh'"
fi

echo ""
echo "📊 Setup complete! You can now:"
echo "  1. View metrics in Prometheus at http://localhost:9090"
echo "  2. Open Grafana at http://localhost:3000"
echo "  3. Inspect MongoDB exporter metrics at http://localhost:9216/metrics"
if [[ "$KEEP_PORT_FORWARDS" == "true" ]]; then
  echo "  4. Stop local port-forwards later with ./stop-monitoring-k8s.sh"
fi

echo ""
echo "🎯 Would you like to generate test metrics now?"
read -r -p "Generate test metrics? (y/N): " REPLY

if [[ "$REPLY" =~ ^[Yy]$ ]]; then
  echo ""
  echo "🚀 Running local metric generation script..."
  if [ -x "./scripts/generate-metrics.sh" ]; then
    K8S_NAMESPACE="$NAMESPACE" ADMIN_PASSWORD="$ADMIN_PASSWORD" ./scripts/generate-metrics.sh k8s
  else
    echo "⚠️  scripts/generate-metrics.sh not found or not executable"
    echo "   Run 'chmod +x scripts/generate-metrics.sh'"
    exit 1
  fi

  echo ""
  echo "🧪 Running strict dashboard metrics test after data generation..."
  if [ -x "./scripts/test-dashboard-metrics.sh" ]; then
    (
      cd scripts
      ./test-dashboard-metrics.sh --strict
    )
  else
    echo "⚠️  scripts/test-dashboard-metrics.sh not found or not executable"
    echo "   Run 'chmod +x scripts/test-dashboard-metrics.sh'"
  fi
else
  echo ""
  echo "💡 To generate metrics later, run:"
  echo "   K8S_NAMESPACE=$NAMESPACE ./scripts/generate-metrics.sh k8s"
fi

echo ""
echo "Done."
