#!/bin/bash

# Stop MongoDB Community Search with Prometheus monitoring

echo "Stopping MongoDB Community Search monitoring stack..."

# Stop all services
docker compose down

echo ""
echo "All services stopped."
echo ""
echo "To completely remove all data (including Grafana dashboards and Prometheus metrics):"
echo "  docker compose down -v"
echo ""
echo "To remove the network:"
echo "  docker network rm search-community"
echo ""