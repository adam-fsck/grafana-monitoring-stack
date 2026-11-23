#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="backups/${STAMP}"
mkdir -p "$DEST"

VOLUMES="grafana_data prometheus_data seaweedfs_data alloy_data entra_exporter_state"

for v in $VOLUMES; do
  docker run --rm \
    -v "grafana-monitoring_${v}:/data:ro" \
    -v "$(pwd)/${DEST}:/backup" \
    busybox tar czf "/backup/${v}.tar.gz" -C /data .
  echo "backed up ${v}"
done

cp .env "${DEST}/.env" 2>/dev/null || echo "WARNING: .env missing, back it up separately"

echo "Done: ${DEST}/"
echo "Copy this directory off-host. It is not offsite by itself."
