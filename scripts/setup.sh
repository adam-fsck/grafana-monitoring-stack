#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -f .env ]; then
  echo ".env exists, skipping."
else
  cp .env.example .env
  sed -i.bak "s/^GRAFANA_ADMIN_PASSWORD=.*/GRAFANA_ADMIN_PASSWORD=$(openssl rand -hex 24)/" .env
  sed -i.bak "s/^SEAWEEDFS_ACCESS_KEY=.*/SEAWEEDFS_ACCESS_KEY=$(openssl rand -hex 16)/" .env
  sed -i.bak "s/^SEAWEEDFS_SECRET_KEY=.*/SEAWEEDFS_SECRET_KEY=$(openssl rand -hex 32)/" .env
  sed -i.bak "s/^SEAWEEDFS_SSE_KEK=.*/SEAWEEDFS_SSE_KEK=$(openssl rand -hex 32)/" .env
  rm -f .env.bak
  chmod 600 .env
  echo ".env generated. Review MONITORING_HOST and ENTRA_* before relying on it."
fi

docker compose config >/dev/null
docker compose pull
docker compose up -d
./scripts/check-stack.sh
