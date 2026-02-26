#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="${K8S_NAMESPACE:-mongodb}"
PORT_FORWARD_TIMEOUT="${PORT_FORWARD_TIMEOUT:-60}"
PROMETHEUS_SCRAPE_WAIT_TIMEOUT="${PROMETHEUS_SCRAPE_WAIT_TIMEOUT:-90}"

FAILED_TESTS=0
PORT_FORWARD_PIDS=()

cleanup() {
  if [ "${#PORT_FORWARD_PIDS[@]}" -gt 0 ]; then
    echo ""
    echo "Stopping temporary port-forwards..."
    for pid in "${PORT_FORWARD_PIDS[@]}"; do
      if kill -0 "$pid" >/dev/null 2>&1; then
        kill "$pid" >/dev/null 2>&1 || true
      fi
    done
  fi
}
trap cleanup EXIT

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "❌ Required command not found: $command_name"
    exit 1
  fi
}

wait_for_endpoint() {
  local url="$1"
  local seconds="$2"

  for _ in $(seq 1 "$seconds"); do
    if curl -s -f "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  return 1
}

ensure_local_endpoint() {
  local url="$1"
  local name="$2"
  local resource="$3"
  local local_port="$4"
  local target_port="$5"

  if curl -s -f "$url" >/dev/null 2>&1; then
    echo "✅ $name is reachable on localhost"
    return 0
  fi

  echo "ℹ️  $name not reachable on localhost. Starting port-forward from $resource..."
  local log_file
  log_file="$(mktemp)"

  kubectl port-forward -n "$NAMESPACE" "$resource" "$local_port:$target_port" >"$log_file" 2>&1 &
  local pf_pid=$!
  PORT_FORWARD_PIDS+=("$pf_pid")

  if wait_for_endpoint "$url" "$PORT_FORWARD_TIMEOUT"; then
    echo "✅ Port-forward ready for $name"
    return 0
  fi

  echo "❌ Failed to make $name reachable at $url"
  echo "Port-forward logs:"
  cat "$log_file"
  ((FAILED_TESTS++))
  return 1
}

test_endpoint() {
  local url="$1"
  local name="$2"
  echo -n "Testing $name ($url): "

  if curl -s -f "$url" >/dev/null 2>&1; then
    echo "✅ OK"
    return 0
  fi

  echo "❌ FAILED"
  ((FAILED_TESTS++))
  return 1
}

test_endpoint_with_content() {
  local url="$1"
  local name="$2"
  local expected_content="$3"
  local optional="${4:-false}"

  echo -n "Testing $name ($url): "

  local response
  response="$(curl -s "$url" 2>/dev/null || true)"

  if [[ -n "$response" && "$response" == *"$expected_content"* ]]; then
    echo "✅ OK"
    return 0
  fi

  if [[ "$optional" == "true" ]]; then
    echo "⚠️  Not found (optional)"
    return 0
  fi

  echo "❌ FAILED"
  ((FAILED_TESTS++))
  return 1
}

wait_for_prometheus_scrape_ready() {
  echo "Waiting for Prometheus scrape targets to be ready..."

  for _ in $(seq 1 "$PROMETHEUS_SCRAPE_WAIT_TIMEOUT"); do
    local targets_response
    local exporter_query_response
    local mongot_query_response

    targets_response="$(curl -s "http://localhost:9090/api/v1/targets" 2>/dev/null || true)"
    exporter_query_response="$(curl -s "http://localhost:9090/api/v1/query?query=up%7Bjob%3D%22mongodb-exporter%22%7D" 2>/dev/null || true)"
    mongot_query_response="$(curl -s "http://localhost:9090/api/v1/query?query=up%7Bjob%3D%22mongot%22%7D" 2>/dev/null || true)"

    if [[ "$targets_response" == *"mongodb-exporter"* ]] && [[ "$targets_response" == *"mongot"* ]] && [[ "$exporter_query_response" == *"mongodb-exporter"* ]] && [[ "$mongot_query_response" == *"mongot"* ]]; then
      echo "✅ Prometheus scrape targets are ready"
      return 0
    fi

    sleep 1
  done

  echo "⚠️  Prometheus scrape targets are still warming up; continuing with checks"
  return 0
}

echo "Testing MongoDB Community Search - Kubernetes Monitoring Setup"
echo "=============================================================="

echo ""
echo "Preparing local access to service endpoints..."

require_command kubectl
require_command curl

ensure_local_endpoint "http://localhost:8080/health" "MongoDB Search Health" "svc/mongodb-search-svc" 8080 8080 || true
ensure_local_endpoint "http://localhost:9946/metrics" "MongoDB Search Metrics" "svc/mongodb-search-svc" 9946 9946 || true
ensure_local_endpoint "http://localhost:9216/metrics" "MongoDB Exporter Metrics" "svc/mongodb-exporter" 9216 9216 || true
ensure_local_endpoint "http://localhost:9090" "Prometheus Web UI" "svc/prometheus" 9090 9090 || true
ensure_local_endpoint "http://localhost:3000" "Grafana Web UI" "svc/grafana" 3000 3000 || true

echo ""
echo "Basic connectivity tests:"
echo "-------------------------"

test_endpoint "http://localhost:8080/health" "MongoDB Search Health" || true
test_endpoint_with_content "http://localhost:9946/metrics" "MongoDB Search Metrics" "# HELP" || true
test_endpoint "http://localhost:9216/metrics" "MongoDB Exporter Metrics" || true
test_endpoint "http://localhost:9090" "Prometheus Web UI" || true
test_endpoint "http://localhost:3000" "Grafana Web UI" || true

echo ""
echo "Prometheus scraping tests:"
echo "--------------------------"

wait_for_prometheus_scrape_ready

test_endpoint_with_content "http://localhost:9090/api/v1/targets" "Prometheus Targets API" "mongodb-exporter" || true
test_endpoint_with_content "http://localhost:9090/api/v1/query?query=up%7Bjob%3D%22mongodb-exporter%22%7D" "MongoDB Exporter Target Status" "mongodb-exporter" || true
test_endpoint_with_content "http://localhost:9090/api/v1/query?query=up%7Bjob%3D%22mongot%22%7D" "Mongot Target Status" "mongot" || true

echo ""
echo "Metrics content tests:"
echo "----------------------"

test_endpoint_with_content "http://localhost:9216/metrics" "MongoDB Metrics Content" "mongodb_up" || true

echo ""
if [[ $FAILED_TESTS -eq 0 ]]; then
  echo "✅ Test completed successfully!"
  echo ""
  echo "You can now:"
  echo "  • View metrics in Prometheus: http://localhost:9090"
  echo "  • Open Grafana dashboard: http://localhost:3000"
  exit 0
fi

echo "❌ Test completed with $FAILED_TESTS failed check(s)."
exit 1
