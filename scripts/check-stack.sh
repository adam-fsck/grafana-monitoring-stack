#!/usr/bin/env bash
set -euo pipefail

check() {
  local name="$1"
  local url="$2"
  printf '%-12s ' "$name"
  if curl -fsS --max-time 5 "$url" >/dev/null; then
    echo "OK"
  else
    echo "FAILED: $url"
    return 1
  fi
}

echo "Docker Compose services:"
docker compose ps

echo
echo "HTTP readiness checks:"
check "Grafana"    "http://127.0.0.1:${GRAFANA_PORT:-5000}/api/health"
check "Prometheus" "http://127.0.0.1:${PROMETHEUS_PORT:-5001}/-/ready"
check "Alloy"      "http://127.0.0.1:${ALLOY_PORT:-5002}/-/ready"
check "cAdvisor"   "http://127.0.0.1:${CADVISOR_PORT:-5003}/healthz"
check "Loki"       "http://127.0.0.1:${LOKI_PORT:-5004}/ready"

echo
echo "All endpoints are ready."
