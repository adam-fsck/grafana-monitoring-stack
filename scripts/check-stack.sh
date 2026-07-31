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
echo "All Docker endpoints are ready."

# -----------------------------------------------------------------------------
# k3s collector (optional)
#
# The Docker part of the stack is checked above and works on its own. Everything
# below only runs when kubectl and a reachable cluster are present, so this
# script stays usable on a pure Docker host.
# -----------------------------------------------------------------------------

if ! command -v kubectl >/dev/null 2>&1; then
  echo
  echo "kubectl not found — skipping k3s checks (Docker-only host)."
  exit 0
fi

if ! kubectl get nodes >/dev/null 2>&1; then
  echo
  echo "No reachable Kubernetes cluster — skipping k3s checks."
  exit 0
fi

echo
echo "k3s collector:"
kubectl -n monitoring get daemonset alloy deployment/kube-state-metrics 2>/dev/null || {
  echo "Not deployed. Apply it with: kubectl apply -f k8s/"
  exit 0
}

echo
echo "k3s collector pods:"
kubectl -n monitoring get pods -o wide

echo
echo "Data actually arriving in Loki from k3s (last 5 minutes):"
# Counts log streams labelled job="k3s-pods". Zero means Alloy is running but
# nothing reaches Loki — usually a wrong LOKI_URL in the alloy-endpoints
# ConfigMap, or Loki not listening on the address the pods can reach.
loki_series=$(curl -fsS --max-time 10 \
  --get "http://127.0.0.1:${LOKI_PORT:-5004}/loki/api/v1/series" \
  --data-urlencode 'match[]={job="k3s-pods"}' \
  --data-urlencode "start=$(( $(date +%s) - 300 ))" 2>/dev/null \
  | grep -o '"container"' | wc -l | tr -d ' ') || loki_series=0

if [ "${loki_series}" -gt 0 ]; then
  echo "OK — ${loki_series} k3s log stream(s) present."
else
  echo "WARNING — no k3s log streams in Loki."
  echo "  Check: kubectl -n monitoring logs daemonset/alloy --tail=50"
fi
