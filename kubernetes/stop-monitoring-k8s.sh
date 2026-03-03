#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

NAMESPACE="${K8S_NAMESPACE:-mongodb}"
DELETE_RESOURCES=false
DELETE_NAMESPACE=false
YES=false

usage() {
  cat <<EOF
Usage: ./kubernetes/stop-monitoring-k8s.sh [options]

Stops common local kubectl port-forwards used by the Kubernetes monitoring helpers.
Can also delete deployed resources.

Options:
  --delete-resources   Delete resources via 'kubectl delete -k kubernetes/'
  --delete-namespace   Delete configured namespace (default: mongodb)
  --yes, -y            Skip confirmation prompts
  --help, -h           Show this help

Environment:
  K8S_NAMESPACE        Kubernetes namespace (default: mongodb)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --delete-resources)
      DELETE_RESOURCES=true
      shift
      ;;
    --delete-namespace)
      DELETE_NAMESPACE=true
      shift
      ;;
    --yes|-y)
      YES=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "❌ Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

confirm() {
  local message="$1"
  if [[ "$YES" == "true" ]]; then
    return 0
  fi

  read -r -p "$message [y/N]: " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

kill_matching_port_forwards() {
  local patterns=(
    "port-forward -n ${NAMESPACE} svc/mongodb-search-svc 8080:8080"
    "port-forward -n ${NAMESPACE} svc/mongodb-search-svc 9946:9946"
    "port-forward -n ${NAMESPACE} svc/mongodb-exporter 9216:9216"
    "port-forward -n ${NAMESPACE} svc/prometheus 9090:9090"
    "port-forward -n ${NAMESPACE} svc/grafana 3000:3000"
    "port-forward -n ${NAMESPACE} svc/mongodb-svc 27017:27017"
  )

  local killed_any=false

  for pattern in "${patterns[@]}"; do
    while IFS= read -r pid; do
      if [[ -n "$pid" ]]; then
        kill "$pid" >/dev/null 2>&1 || true
        echo "🛑 Stopped port-forward process PID $pid"
        killed_any=true
      fi
    done < <(pgrep -f "$pattern" || true)
  done

  if [[ "$killed_any" == "false" ]]; then
    echo "ℹ️  No matching port-forward processes found."
  fi
}

echo "Stopping Kubernetes monitoring helpers (namespace: $NAMESPACE)..."

echo ""
echo "Checking and stopping common local port-forwards..."
kill_matching_port_forwards

if [[ "$DELETE_RESOURCES" == "true" ]]; then
  echo ""
  if confirm "Delete resources managed by kustomization in the current folder?"; then
    kubectl delete -k "$SCRIPT_DIR" || true
    echo "🧹 Requested deletion of kustomize-managed resources."
  else
    echo "Skipped resource deletion."
  fi
fi

if [[ "$DELETE_NAMESPACE" == "true" ]]; then
  echo ""
  if confirm "Delete namespace '$NAMESPACE'? This removes everything in it."; then
    kubectl delete namespace "$NAMESPACE" || true
    echo "🧹 Requested deletion of namespace '$NAMESPACE'."
  else
    echo "Skipped namespace deletion."
  fi
fi

echo ""
echo "Done."
