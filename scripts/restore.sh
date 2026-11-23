#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

BACKUP_DIR="${1:?Usage: scripts/restore.sh backups/<timestamp>}"
VOLUMES="grafana_data prometheus_data seaweedfs_data alloy_data entra_exporter_state"

docker compose down

for v in $VOLUMES; do
  f="${BACKUP_DIR}/${v}.tar.gz"
  [ -f "$f" ] || { echo "skip ${v}, no ${f}"; continue; }
  docker volume create "grafana-monitoring_${v}" >/dev/null
  docker run --rm \
    -v "grafana-monitoring_${v}:/data" \
    -v "$(pwd)/${BACKUP_DIR}:/backup:ro" \
    busybox sh -c "rm -rf /data/* && tar xzf /backup/${v}.tar.gz -C /data"
  echo "restored ${v}"
done

if [ -f "${BACKUP_DIR}/.env" ] && [ ! -f .env ]; then
  cp "${BACKUP_DIR}/.env" .env
  echo "restored .env"
fi

docker compose up -d
./scripts/check-stack.sh
