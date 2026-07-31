# Monitoring stack: Grafana + Alloy + Prometheus + cAdvisor + Loki

Production-oriented single-host monitoring for an Ubuntu server running
**Docker, k3s, or both side by side**. It automatically discovers all current
and future workloads and collects:

- CPU usage
- RAM working-set usage
- Network receive/transmit throughput
- Container filesystem read/write throughput
- Container `stdout` and `stderr` logs
- Kubernetes pod health: restarts, readiness, phase (k3s only)
- End-to-end HTTP health probes of the public API endpoints (k3s only)
- Basic self-monitoring metrics for Grafana, Alloy, Prometheus and Loki

Ready-made Grafana dashboards and both data sources are provisioned
automatically.

Docker and k3s collection are independent. Running only Docker needs nothing
from the `k8s/` directory; adding k3s leaves the Docker path untouched. Logs
from the two are separated by the `job` label — `docker-containers` versus
`k3s-pods` — so dashboards for one never mix in data from the other.

## Included versions

| Component | Image |
|---|---|
| Grafana | `grafana/grafana:13.1.1` |
| Grafana Alloy | `grafana/alloy:v1.18.0` |
| Prometheus | `prom/prometheus:v3.13.1` |
| cAdvisor | `ghcr.io/google/cadvisor:v0.60.5` |
| Loki | `grafana/loki:3.7.2` |

Versions are pinned deliberately. A normal restart therefore cannot silently
upgrade the stack to an incompatible release.

## Data flow

```text
Docker container metrics ──> cAdvisor ──────> Alloy ──> Prometheus ──> Grafana
Docker stdout/stderr logs ───────────────────> Alloy ──> Loki ───────> Grafana

k3s pod logs ────────────────> Alloy (DaemonSet) ──────> Loki ───────> Grafana
k3s pod CPU/RAM/net/disk ────> kubelet cAdvisor ──┐
k3s restarts / readiness ────> kube-state-metrics ─┼─> Alloy ──> Prometheus ──> Grafana
public /health probes ───────> blackbox ──────────┘
```

Grafana, Prometheus and Loki always run in Docker. In a k3s setup the only
in-cluster components are Alloy (collector) and kube-state-metrics (producer of
health metrics).

The in-cluster Alloy runs with `hostNetwork: true`, so `127.0.0.1` inside that
pod is the **server's** loopback. It therefore reaches the Loki and Prometheus
ports Docker publishes on `127.0.0.1`, and those two stay bound to localhost —
adding k3s does not expose anything to the network.

## Ports

All published host ports are in the `5000+` range.

| Service | Host port | Container port | Default bind |
|---|---:|---:|---|
| Grafana | `5000` | `3000` | `0.0.0.0` |
| Prometheus | `5001` | `9090` | `127.0.0.1` |
| Alloy UI | `5002` | `12345` | `127.0.0.1` |
| cAdvisor UI | `5003` | `8080` | `127.0.0.1` |
| Loki | `5004` | `3100` | `127.0.0.1` |

Only Grafana is remotely reachable by default. Prometheus, Alloy, cAdvisor and
Loki have no authentication in this single-host configuration, so they remain
bound to localhost. Do not change `MONITORING_BIND_ADDRESS` to `0.0.0.0` unless
a firewall or authenticated reverse proxy restricts access.

## 1. Upload and unpack

Example target directory:

```bash
sudo mkdir -p /opt/monitoring
sudo chown "$USER":"$USER" /opt/monitoring
cd /opt/monitoring
```

Copy the ZIP file to the server and unpack it:

```bash
unzip grafana-monitoring-stack-complete.zip
cd grafana-monitoring-stack-complete
```

If `unzip` is unavailable:

```bash
sudo apt update
sudo apt install -y unzip
```

## 2. Create `.env`

```bash
cp .env.example .env
```

Generate a password containing safe hexadecimal characters:

```bash
openssl rand -hex 24
```

Edit the configuration:

```bash
nano .env
```

At minimum, replace:

```env
GRAFANA_ADMIN_PASSWORD=CHANGE_ME_TO_A_LONG_RANDOM_PASSWORD
MONITORING_HOST=UBUNTU-PROD
```

`MONITORING_HOST` becomes a Loki log label. Use a stable host name, especially
if you later send data from multiple servers into one monitoring stack.

Protect the file:

```bash
chmod 600 .env
```

## 3. Validate and start

```bash
docker compose config
docker compose pull
docker compose up -d
docker compose ps
```

Expected containers:

```text
grafana
prometheus
alloy
cadvisor
loki
```

The first Loki startup can take several seconds.

## 4. Run the included health check

```bash
chmod +x scripts/check-stack.sh
./scripts/check-stack.sh
```

Manual checks:

```bash
curl -fsS http://127.0.0.1:5001/-/ready
curl -fsS http://127.0.0.1:5002/-/ready
curl -fsS http://127.0.0.1:5003/healthz
curl -fsS http://127.0.0.1:5004/ready
curl -fsS http://127.0.0.1:5000/api/health
```

If a service fails:

```bash
docker compose ps
docker compose logs --tail=200 alloy
docker compose logs --tail=200 cadvisor
docker compose logs --tail=200 loki
```

## 5. Open Grafana

Open:

```text
http://SERVER_IP:5000
```

Log in with `GRAFANA_ADMIN_USER` and `GRAFANA_ADMIN_PASSWORD` from `.env`.

The following are provisioned automatically:

- Prometheus data source
- Loki data source
- Folder: **Monitoring**
- Dashboard: **Docker Containers — Metrics and Logs**

The dashboard contains CPU, RAM, network, disk I/O and log panels with a
container filter.

## 6. Verify container metrics

Check that cAdvisor exposes metrics:

```bash
curl -fsS http://127.0.0.1:5003/metrics | head
```

Check Prometheus through its HTTP API:

```bash
curl -fsSG \
  --data-urlencode 'query=up' \
  http://127.0.0.1:5001/api/v1/query
```

Useful PromQL queries in Grafana **Explore → Prometheus**:

### CPU by container

```promql
sum by (name) (
  rate(container_cpu_usage_seconds_total{name!="",image!=""}[5m])
)
```

The value is CPU cores consumed. `1.0` means one full logical CPU core.

### RAM by container

```promql
sum by (name) (
  container_memory_working_set_bytes{name!="",image!=""}
)
```

### Network receive

```promql
sum by (name) (
  rate(container_network_receive_bytes_total{name!="",image!=""}[5m])
)
```

### Network transmit

```promql
sum by (name) (
  rate(container_network_transmit_bytes_total{name!="",image!=""}[5m])
)
```

## 7. Verify Docker logs

Alloy collects the same container output that is accessible through
`docker logs`.

Verify that an application emits logs:

```bash
docker logs --tail=20 coachlink-api-prod
```

Then open **Grafana → Explore → Loki** and run:

```logql
{job="docker-containers"}
```

Filter a specific container:

```logql
{job="docker-containers", container="coachlink-api-prod"}
```

For Spring Boot JSON logs, parse fields at query time:

```logql
{container="coachlink-api-prod"} | json
```

Logs written only to a file inside a container are not collected by this
pipeline. Applications should write operational logs to `stdout`/`stderr`.

Check logging drivers for every running container:

```bash
docker ps -q | xargs -r docker inspect \
  --format '{{.Name}} -> {{.HostConfig.LogConfig.Type}}'
```

A container configured with logging driver `none` has no logs to collect.

## 8. Configure Docker log rotation

Loki retention does not control the local Docker log files. Configure Docker
log rotation separately so `json-file` logs cannot fill the system disk.

First inspect the existing configuration:

```bash
sudo cat /etc/docker/daemon.json 2>/dev/null || echo 'No daemon.json exists'
```

The file `examples/daemon.json.logging-rotation.example` contains this example:

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "20m",
    "max-file": "5"
  }
}
```

**Merge these keys into the existing JSON. Do not overwrite unrelated Docker
settings.** Validate the resulting file:

```bash
python3 -m json.tool /etc/docker/daemon.json >/dev/null
```

Docker daemon restart interrupts Docker networking and may restart containers.
Perform it in a maintenance window:

```bash
sudo systemctl restart docker
```

Default logging settings apply only to newly created containers. Recreate
existing Compose services during a planned deployment to apply them.

## 9. Nginx Proxy Manager

Only proxy Grafana. Create a Proxy Host with:

```text
Scheme: http
Forward hostname/IP: SERVER_LAN_IP
Forward port: 5000
Websockets support: enabled
```

Enable SSL and **Force SSL**. Do not publish Prometheus, Loki, Alloy or cAdvisor
without a separate authentication layer.

If Nginx Proxy Manager cannot reach port `5000`, verify:

```bash
ss -lntp | grep ':5000'
curl -fsS http://SERVER_LAN_IP:5000/api/health
```

## 10. Retention and persistent data

Defaults:

- Prometheus metrics: `30d`, controlled by `PROMETHEUS_RETENTION`
- Loki logs: `720h` / 30 days, configured in `loki/loki.yml`

Persistent named volumes:

```text
grafana_data
prometheus_data
alloy_data
loki_data
```

A normal shutdown preserves data:

```bash
docker compose down
```

This command permanently deletes all monitoring data and should be used only
when explicitly intended:

```bash
docker compose down -v
```

Monitor disk consumption:

```bash
docker system df -v
docker exec prometheus du -sh /prometheus
docker exec loki du -sh /loki
```

## 11. Collect from k3s (optional)

Skip this section entirely on a Docker-only host. The Docker collection
described above keeps working exactly as before whether or not k3s is present.

### 11.1 What gets deployed

Everything lands in the `monitoring` namespace:

| Object | Purpose |
|---|---|
| `alloy` (DaemonSet) | Reads pod logs and scrapes kubelet metrics on every node |
| `kube-state-metrics` (Deployment) | Produces health metrics: restarts, readiness, phase |
| `alloy-config` (ConfigMap) | Alloy pipeline definition |
| `alloy-endpoints` (ConfigMap) | Where to ship data, and which URLs to health-probe |

### 11.2 Check the endpoints first

`k8s/15-alloy-endpoints.yaml` assumes the defaults from `.env` — Loki on
`5004`, Prometheus on `5001`, both on the same server. If those ports were
changed, or the health probe should point elsewhere, edit that file before
applying:

```bash
nano k8s/15-alloy-endpoints.yaml
```

### 11.3 Apply

```bash
kubectl apply -f k8s/
```

### 11.4 Verify

```bash
kubectl -n monitoring get pods
kubectl -n monitoring logs daemonset/alloy --tail=50
```

`alloy` should be `Running` on every node and `kube-state-metrics` `Running`
once. The bundled script also checks whether data actually lands in Loki:

```bash
./scripts/check-stack.sh
```

Confirm logs are arriving, replacing the namespace with your own:

```bash
curl -s -G 'http://127.0.0.1:5004/loki/api/v1/query' \
  --data-urlencode 'query={job="k3s-pods", namespace="coachlink"}' | head -c 400
```

In Grafana, open the **CoachLink BE — k3s (dev + prod)** dashboard. Pick a
namespace and containers at the top; dev and prod are separated by the
container name, and every pod log also carries an `env` label (`dev` / `prod`)
derived from that name.

### 11.5 After changing the Alloy config

A mounted ConfigMap updates itself, but Alloy does not re-read it. Restart the
DaemonSet after editing `k8s/20-alloy-config.yaml`:

```bash
kubectl apply -f k8s/20-alloy-config.yaml
kubectl -n monitoring rollout restart daemonset/alloy
```

### 11.6 Removing the k3s collector

```bash
kubectl delete -f k8s/
```

The Docker stack is unaffected.

## 12. Updating the stack

The images are pinned. To apply the same pinned images again:

```bash
docker compose pull
docker compose up -d
```

Before changing version tags, review component release notes and back up the
Grafana, Prometheus and Loki volumes.

## Troubleshooting

### Alloy reports permission denied for Docker socket

The provided Compose file runs Alloy as root specifically to guarantee access
to `/var/run/docker.sock` on a Linux Docker host. Confirm the mount:

```bash
docker inspect alloy --format '{{json .Mounts}}' | python3 -m json.tool
```

The Docker socket effectively grants host-level Docker control. Do not install
untrusted Alloy components or expose the Alloy configuration to untrusted users.

### cAdvisor exits because `/dev/kmsg` is missing

Check:

```bash
ls -l /dev/kmsg
```

On restricted LXC environments the device may not exist. On a normal Ubuntu VM
it should be present. If the host has no `/dev/kmsg`, remove this block from the
`cadvisor` service and retry:

```yaml
devices:
  - /dev/kmsg:/dev/kmsg
```

### Metrics are absent but cAdvisor is running

```bash
curl -fsS http://127.0.0.1:5003/metrics | grep container_cpu_usage_seconds_total | head
docker compose logs --tail=200 alloy
```

Open the Alloy UI locally at `http://127.0.0.1:5002` or use an SSH tunnel:

```bash
ssh -L 5002:127.0.0.1:5002 user@SERVER_IP
```

### Logs are absent

```bash
docker logs --tail=50 CONTAINER_NAME
docker compose logs --tail=200 alloy
curl -fsS http://127.0.0.1:5004/ready
```

Confirm that the application writes to stdout/stderr and does not use logging
driver `none`.

### No k3s logs or metrics reach the stack

```bash
kubectl -n monitoring get pods
kubectl -n monitoring logs daemonset/alloy --tail=100
```

Work through these in order:

1. **`CrashLoopBackOff` on `alloy`** — usually a syntax error in
   `k8s/20-alloy-config.yaml`. The reason is in the pod log.
2. **`connection refused` to Loki or Prometheus** — the DaemonSet must run with
   `hostNetwork: true` for `127.0.0.1` to mean the server. Verify the ports in
   `k8s/15-alloy-endpoints.yaml` match `LOKI_PORT` and `PROMETHEUS_PORT`
   in `.env`.
3. **Logs arrive but metrics do not** — the kubelet scrape needs the RBAC in
   `k8s/10-alloy-rbac.yaml`; `403` in the Alloy log means it was not applied.
4. **`probe_success` missing** — check the URLs in `HEALTH_URL_DEV` and
   `HEALTH_URL_PROD`; they are probed from the server, so any name used there
   must resolve on it.

Check what Loki actually received:

```bash
curl -s -G 'http://127.0.0.1:5004/loki/api/v1/series' \
  --data-urlencode 'match[]={job="k3s-pods"}' | head -c 400
```

### CPU or RAM per pod looks roughly twice as high as expected

cAdvisor reports a per-container series **and** a pod-level aggregate whose
`container` label is empty. Summing both double-counts. Every query in the
bundled dashboard filters with `container!=""`; keep that filter in custom
panels too.
