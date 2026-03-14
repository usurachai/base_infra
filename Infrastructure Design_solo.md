# Infrastructure Design — Solo Founder Edition

> Adapted from [Infrastructure Design_2.md](file:///Users/surachai/dev/zendesk-agent/Infrastructure%20Design_2.md) for a **single person** who ships product, runs infra, and sleeps at night.

---

## Philosophy: Solo ≠ Sloppy

The v2 design is architecturally sound but demands **team-level operational overhead** (4 networks, 13+ containers, YAML contracts, Alertmanager runbooks). A solo founder needs:

| Team Design | Solo Adjustment |
|---|---|
| Blast-radius containment across teams | You're the only blast radius — simplify isolation |
| Contract YAML between repos | You know both services — use conventions, not contracts |
| 4 segmented Docker networks | 2 networks (frontend + internal) — still isolated, less config |
| 13+ containers | 10 containers — cut exporters, merge where possible |
| 3 independent Git repos with heavy ceremony | **3 repos** kept, but with a thin orchestration script instead of contracts |
| Alertmanager + PagerDuty | Grafana alerting → Telegram/email — zero extra containers |
| SSH tunnel for management UIs | Direct host ports with IP allowlist or Tailscale |

> [!IMPORTANT]
> This design intentionally trades **defense-in-depth for cognitive load reduction**. Every piece you cut is documented with a "when to add it back" trigger so you know exactly when to scale up.

---

## Design Principles (Solo-Adapted)

| # | Principle | Solo Application |
|---|---|---|
| 1 | **Minimum Viable Security** | 2-network isolation + Redis AUTH + PG roles — no mTLS overhead |
| 2 | **Three Repos, One Script** | Separate repos for infra / chat / rag — orchestrated by a thin deploy script |
| 3 | **Automate the Boring, Skip the Rare** | Automated backups + health checks; skip Alertmanager until revenue |
| 4 | **Observable Enough** | Grafana for logs + metrics, Jaeger for traces. No cAdvisor, node-exporter, or Alertmanager |
| 5 | **Sleep-Safe Defaults** | Resource limits + automatic restart policies + daily backup cron |

---

## High-Level Architecture

```mermaid
graph TB
    subgraph Internet
        Client["🌐 Client"]
    end

    subgraph infra["📦 infra-platform repo"]
        subgraph infra_layer["Infrastructure"]
            NGINX["nginx :443/:80"]
            PG[("PostgreSQL 16<br/>+ pgvector")]
            REDIS[("Redis 7<br/>cache + queue")]
        end

        subgraph observe_logs_metrics["Logs + Metrics"]
            PROM["Prometheus"]
            GRAF["Grafana :3000"]
            LOKI["Loki"]
        end

        subgraph observe_traces["Traces"]
            JAEGER["Jaeger :16686"]
        end
    end

    subgraph svc1["📂 chat-api repo"]
        CHAT_API["chat-api :8000"]
        CHAT_WORKER["chat-worker"]
    end

    subgraph svc2["📂 rag-service repo"]
        RAG_API["rag-api :8001"]
    end

    Client -->|HTTPS| NGINX
    NGINX -->|"/api/chat/*"| CHAT_API
    NGINX -->|"/api/rag/*"| RAG_API

    CHAT_API --> PG
    CHAT_API --> REDIS
    CHAT_WORKER --> PG
    CHAT_WORKER --> REDIS
    RAG_API --> PG
    RAG_API --> REDIS

    CHAT_API -.->|OTLP| JAEGER
    RAG_API -.->|OTLP| JAEGER
    CHAT_API -.->|"/metrics"| PROM
    RAG_API -.->|"/metrics"| PROM

    LOKI --> GRAF
    PROM --> GRAF

    style infra fill:#f0f4ff,stroke:#4a6fa5,color:#1a1a2e
    style infra_layer fill:#e3f2fd,stroke:#1976d2,color:#1a1a2e
    style observe_logs_metrics fill:#fff8e1,stroke:#ff8f00,color:#1a1a2e
    style observe_traces fill:#fce4ec,stroke:#e53935,color:#1a1a2e
    style svc1 fill:#e8f5e9,stroke:#4caf50,color:#1a1a2e
    style svc2 fill:#f3e5f5,stroke:#9c27b0,color:#1a1a2e
```

---

## Network Model: 2 Networks (Down from 4)

```mermaid
graph TB
    subgraph networks["Docker Networks"]
        direction LR
        subgraph net_frontend["🔴 frontend-net"]
            N_NGX["nginx"]
            N_CHAT["chat-api"]
            N_RAG["rag-api"]
        end

        subgraph net_internal["🔵 internal-net"]
            N_PG["postgres"]
            N_REDIS["redis"]
            N_PROM["prometheus"]
            N_GRAF["grafana"]
            N_LOKI["loki"]
            N_JAEGER["jaeger"]
            N_CHAT2["chat-api"]
            N_RAG2["rag-api"]
            N_WORKER["chat-worker"]
        end
    end

    style net_frontend fill:#fce4ec,stroke:#e53935,color:#1a1a2e
    style net_internal fill:#e3f2fd,stroke:#1976d2,color:#1a1a2e
```

| Network | Purpose | Who Joins |
|---|---|---|
| `frontend-net` | HTTP traffic only — NGINX ↔ app backends | nginx, chat-api, rag-api |
| `internal-net` | Data + observability — everything backend | postgres, redis, prometheus, grafana, loki, jaeger, chat-api, rag-api, chat-worker |

**Why not 1 flat network?** Even solo, separating frontend from internal means a compromised NGINX can't hit Postgres directly. Minimal config overhead, real security win.

**Why not 4 networks?** Separate observability-net and management-net add config weight without meaningful blast-radius reduction when you're the only operator. Each extra network = more Docker Compose lines to debug at 2 AM.

> [!NOTE]
> **When to add network 3 & 4**: When you hire your first infrastructure engineer, or when you move to Kubernetes (where NetworkPolicies make segmentation free).

---

## Three-Repo Structure

Three independent Git repos, each with its own `docker-compose.yml`. The infra repo **creates** the shared Docker networks; app repos **join** them as external.

### Repo 1: `infra-platform/`

```
infra-platform/
├── docker-compose.yml          # Infra services only
├── .env.example
├── Makefile                    # Infra ops
├── nginx/
│   ├── nginx.conf
│   └── conf.d/
│       ├── upstreams.conf      # App service upstreams
│       └── routes.conf
├── postgres/
│   ├── init.sql                # Roles + schemas
│   └── pg_hba.conf
├── prometheus/
│   └── prometheus.yml
├── loki/
│   └── loki-config.yml
├── grafana/
│   └── provisioning/
│       ├── datasources/
│       ├── dashboards/
│       └── alerting/
├── scripts/
│   ├── backup.sh               # Automated PG backup
│   ├── healthcheck.sh
│   └── deploy-all.sh           # Orchestrates all 3 repos
└── README.md
```

### Repo 2: `chat-api/`

```
chat-api/
├── docker-compose.yml          # networks: external
├── .env.example
├── Makefile
├── Dockerfile
├── app/
│   ├── main.py
│   ├── routers/
│   └── worker/
└── tests/
```

### Repo 3: `rag-service/`

```
rag-service/
├── docker-compose.yml          # networks: external
├── .env.example
├── Makefile
├── Dockerfile
├── app/
│   ├── main.py
│   ├── routers/
│   └── ingestion/
└── tests/
```

### Observability Workflow

| Tool | What You Use It For | URL |
|---|---|---|
| **Grafana** | Log search (Loki datasource), metric dashboards (Prometheus datasource), alerting | `:3000` |
| **Jaeger** | Trace inspection, request flow debugging, latency analysis | `:16686` |

> [!NOTE]
> Jaeger is **not** wired as a Grafana datasource. You go to Jaeger UI directly for trace operations. This avoids the overhead of configuring Tempo/Jaeger datasource in Grafana and keeps each tool focused on what it does best.

### How They Connect

The infra repo creates the shared networks. App repos reference them as `external: true`:

```yaml
# chat-api/docker-compose.yml (same pattern for rag-service)
services:
  chat-api:
    build: .
    networks:
      - frontend-net
      - internal-net
    environment:
      - DATABASE_URL=postgresql://chat_app:${CHAT_DB_PASSWORD}@postgres:5432/postgres?options=-csearch_path=chat
      - REDIS_URL=redis://:${REDIS_PASSWORD}@redis:6379/0
      - OTEL_EXPORTER_OTLP_ENDPOINT=http://jaeger:4318
    restart: unless-stopped

  chat-worker:
    build: .
    command: python -m app.worker.runner
    networks:
      - internal-net
    restart: unless-stopped

networks:
  frontend-net:
    external: true
  internal-net:
    external: true
```

### Orchestration Script (Keeps It Simple)

```bash
#!/bin/bash
# infra-platform/scripts/deploy-all.sh
# One script to deploy everything in the right order

set -euo pipefail

PROJECT_ROOT="$(dirname "$(dirname "$(realpath "$0")")")/.."
INFRA_DIR="$PROJECT_ROOT/infra-platform"
CHAT_DIR="$PROJECT_ROOT/chat-api"
RAG_DIR="$PROJECT_ROOT/rag-service"

echo "=== 1/3 Infrastructure ==="
cd "$INFRA_DIR" && git pull && docker compose up -d --build
echo "Waiting for infra health checks..."
sleep 10

echo "=== 2/3 Chat API ==="
cd "$CHAT_DIR" && git pull && docker compose up -d --build

echo "=== 3/3 RAG Service ==="
cd "$RAG_DIR" && git pull && docker compose up -d --build

echo "=== Health Check ==="
sleep 5
curl -sf http://localhost:8000/health/ready && echo " ✅ chat-api" || echo " ❌ chat-api"
curl -sf http://localhost:8001/health/ready && echo " ✅ rag-api"  || echo " ❌ rag-api"
docker compose -f "$INFRA_DIR/docker-compose.yml" ps
```

> [!TIP]
> **Local dev setup**: Clone all 3 repos as siblings in one parent directory. The deploy script assumes:
> ```
> ~/projects/
> ├── infra-platform/
> ├── chat-api/
> └── rag-service/
> ```

> [!IMPORTANT]
> **Config sync**: Each repo has its own `.env.example`. Shared values (DB passwords, Redis password) must match across repos. Use a single `.env` template in the infra repo's README and copy values to each app repo's `.env`.

---

## Containers: What Stays, What Goes

| Container | v2 (Team) | Solo | Rationale |
|---|---|---|---|
| nginx | ✅ | ✅ | Reverse proxy is non-negotiable |
| postgres | ✅ | ✅ | Primary data store |
| redis | ✅ | ✅ | Cache + task queue |
| chat-api | ✅ | ✅ | Core app |
| chat-worker | ✅ | ✅ | Background jobs |
| rag-api | ✅ | ✅ | Core app |
| prometheus | ✅ | ✅ | Metrics — lightweight, essential |
| grafana | ✅ | ✅ | Single pane of glass for all observability |
| loki | ✅ | ✅ | Centralized logs — beats `docker logs` |
| jaeger | ✅ | ✅ | Distributed tracing — critical for debugging cross-service calls |
| **promtail** | ✅ | ❌ | **Use Loki Docker log driver instead** — zero extra container |
| **alertmanager** | ✅ | ❌ | **Grafana has built-in alerting** — direct to Telegram/Email/Slack |
| **node-exporter** | ✅ | ❌ | Add back when you need host-level metrics (multi-node) |
| **cAdvisor** | ✅ | ❌ | Docker metrics available via Prometheus Docker daemon metrics |
| **postgres-exporter** | ✅ | ❌ | Add back when PG performance tuning matters (>100 RPS) |
| **redis-exporter** | ✅ | ❌ | Add back when Redis memory/eviction debugging is needed |

**Result: 10 containers** (down from 16) — less RAM, less CPU, less noise in `docker ps`.

> [!TIP]
> **Loki Docker log driver** replaces Promtail entirely. Add this to your Docker daemon config (`/etc/docker/daemon.json`):
> ```json
> {
>   "log-driver": "loki",
>   "log-opts": {
>     "loki-url": "http://localhost:3100/loki/api/v1/push",
>     "loki-batch-size": "400"
>   }
> }
> ```
> All container stdout/stderr goes to Loki automatically. Zero sidecar containers.

---

## Security: Pragmatic, Not Paranoid

| Concern | v2 (Team) | Solo | Why |
|---|---|---|---|
| Network isolation | 4 networks | **2 networks** | Still isolated; less config |
| Redis AUTH | Per-service tokens | **Single password** | You're the only client; rotate quarterly |
| PostgreSQL roles | Per-service roles + schema grants | **Per-service roles + schema grants** | ✅ Keep this — protects against app bugs |
| Secrets management | Docker secrets (file-based) | **`.env` file with `chmod 600`** | Docker secrets add complexity for zero team benefit |
| Internal TLS (mTLS) | Optional upgrade path | **Skip entirely** | All traffic is on localhost Docker networks |
| Resource limits | Per-container | **Per-container** | ✅ Keep this — prevents OOM killing your DB |
| Read-only filesystems | Per-container | **Skip** | Nice-to-have; add when you have time |

### PostgreSQL Role Isolation (Keep!)

```sql
-- infra-platform/postgres/init.sql

-- Per-service roles (no superuser)
CREATE ROLE chat_app LOGIN PASSWORD '${CHAT_DB_PASSWORD}';
CREATE ROLE rag_app  LOGIN PASSWORD '${RAG_DB_PASSWORD}';

-- Per-service schemas
CREATE SCHEMA chat AUTHORIZATION chat_app;
CREATE SCHEMA rag  AUTHORIZATION rag_app;

-- Grants
GRANT USAGE ON SCHEMA chat TO chat_app;
GRANT ALL ON ALL TABLES IN SCHEMA chat TO chat_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA chat GRANT ALL ON TABLES TO chat_app;

GRANT USAGE ON SCHEMA rag TO rag_app;
GRANT ALL ON ALL TABLES IN SCHEMA rag TO rag_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA rag GRANT ALL ON TABLES TO rag_app;

-- pgvector (shared)
CREATE EXTENSION IF NOT EXISTS vector;
```

> [!IMPORTANT]
> PG role isolation is the **one security item you must never skip**, even solo. A bug in chat-api that does `DROP TABLE` only drops chat tables, not rag tables.

---

## Resource Limits (Right-Sized for Solo VPS)

Tuned for a **4 vCPU / 8 GB RAM** VPS (e.g. Hetzner CX41 ~€15/mo or DigitalOcean 8GB ~$48/mo):

```yaml
services:
  # === Data Layer (priority: HIGH) ===
  postgres:
    deploy:
      resources:
        limits:   { cpus: "2.0",  memory: "2G" }
        reservations: { cpus: "0.5", memory: "512M" }
    restart: unless-stopped

  redis:
    deploy:
      resources:
        limits:   { cpus: "0.5",  memory: "512M" }
        reservations: { cpus: "0.1", memory: "64M" }
    restart: unless-stopped

  # === Application Layer (priority: HIGH) ===
  chat-api:
    deploy:
      resources:
        limits:   { cpus: "1.0",  memory: "1G" }
        reservations: { cpus: "0.25", memory: "256M" }
    restart: unless-stopped

  rag-api:
    deploy:
      resources:
        limits:   { cpus: "1.0",  memory: "1G" }
        reservations: { cpus: "0.25", memory: "256M" }
    restart: unless-stopped

  chat-worker:
    deploy:
      resources:
        limits:   { cpus: "0.5",  memory: "512M" }
    restart: unless-stopped

  # === Edge Layer ===
  nginx:
    deploy:
      resources:
        limits:   { cpus: "0.5",  memory: "128M" }
    restart: unless-stopped

  # === Observability: Logs + Metrics (priority: LOW — shed these first) ===
  prometheus:
    deploy:
      resources:
        limits:   { cpus: "0.5",  memory: "512M" }
    restart: unless-stopped

  grafana:
    deploy:
      resources:
        limits:   { cpus: "0.5",  memory: "256M" }
    restart: unless-stopped

  loki:
    deploy:
      resources:
        limits:   { cpus: "0.5",  memory: "256M" }
    restart: unless-stopped

  # === Observability: Traces ===
  jaeger:
    deploy:
      resources:
        limits:   { cpus: "0.5",  memory: "512M" }
    restart: unless-stopped
```

**Total reserved: ~3.1 GB RAM / ~1.85 vCPU** — leaves plenty of headroom on a 8 GB box.

---

## Startup Order (Simplified)

```mermaid
flowchart TD
    START(["deploy-all.sh"]) --> INFRA_UP["infra-platform<br/>docker compose up"]
    INFRA_UP --> PG["postgres"]
    INFRA_UP --> REDIS["redis"]
    INFRA_UP --> LOKI["loki"]
    INFRA_UP --> PROM["prometheus"]
    INFRA_UP --> JAEGER["jaeger"]

    PG -->|healthy| NGINX["nginx"]
    REDIS -->|healthy| NGINX

    INFRA_UP -.->|"networks created"| APP_PHASE

    subgraph APP_PHASE["App Repos (separate docker compose up)"]
        direction LR
        CHAT["chat-api<br/>chat-worker"]
        RAG["rag-api"]
    end

    CHAT -->|"depends_on: postgres, redis"| PG
    RAG -->|"depends_on: postgres, redis"| PG

    APP_PHASE -.->|"/health/ready → 200"| NGINX_ROUTE["nginx routes<br/>traffic to healthy<br/>backends"]

    PROM --> GRAF["grafana<br/>(logs + metrics)"]
    LOKI --> GRAF

    classDef db fill:#e3f2fd,stroke:#1976d2,color:#1a1a2e
    classDef app fill:#e8f5e9,stroke:#4caf50,color:#1a1a2e
    classDef obs fill:#fff8e1,stroke:#ff8f00,color:#1a1a2e
    classDef proxy fill:#fce4ec,stroke:#e53935,color:#1a1a2e

    class PG,REDIS db
    class CHAT,RAG app
    class PROM,GRAF,LOKI,JAEGER obs
    class NGINX,NGINX_ROUTE proxy
```

**Key difference from v2**: The `deploy-all.sh` script handles the startup order across repos — infra first (creates networks + data stores), then app repos join. NGINX starts with infra and returns 503 until app backends pass health checks. No complex cross-compose `depends_on` needed — NGINX's `proxy_next_upstream` handles it.

---

## Grafana Alerting (Replaces Alertmanager)

Instead of running a separate Alertmanager container, use **Grafana's built-in alerting**:

```yaml
# infra-platform/grafana/provisioning/alerting/alerts.yml
apiVersion: 1
groups:
  - orgId: 1
    name: critical
    folder: Alerts
    interval: 1m
    rules:
      - uid: service-down
        title: Service Down
        condition: C
        data:
          - refId: A
            queryType: ""
            datasourceUid: prometheus
            model:
              expr: up{job=~"chat-api|rag-api"} == 0
              intervalMs: 1000
        for: 2m
        annotations:
          summary: "{{ $labels.job }} is DOWN"

      - uid: high-error-rate
        title: High Error Rate
        condition: C
        data:
          - refId: A
            datasourceUid: prometheus
            model:
              expr: |
                rate(http_requests_total{status=~"5.."}[5m])
                / rate(http_requests_total[5m]) > 0.05
        for: 5m
        annotations:
          summary: ">5% error rate on {{ $labels.job }}"

      - uid: disk-usage
        title: Disk Usage High
        condition: C
        data:
          - refId: A
            datasourceUid: prometheus
            model:
              expr: |
                (node_filesystem_size_bytes{mountpoint="/"} - node_filesystem_free_bytes{mountpoint="/"})
                / node_filesystem_size_bytes{mountpoint="/"} > 0.85
        for: 10m
        annotations:
          summary: "Disk usage above 85%"

      - uid: pg-connections
        title: PostgreSQL Connection Saturation
        condition: C
        data:
          - refId: A
            datasourceUid: prometheus
            model:
              expr: |
                pg_stat_activity_count / pg_settings_max_connections > 0.8
        for: 5m
        annotations:
          summary: "PG connections above 80% capacity"
```

**Contact points**: Configure Telegram bot or email in Grafana UI — takes 2 minutes, zero YAML.

---

## Makefile: Your Daily Ops Interface

Each repo has its own `Makefile` for local ops. The **infra repo** also has cross-repo commands.

### infra-platform/Makefile

```makefile
# infra-platform/Makefile — infrastructure + cross-repo ops

.PHONY: up down status backup deploy-all health

# === Infrastructure Only ===
up:
	docker compose up -d

down:
	docker compose down

logs:
	docker compose logs -f --tail=100 $(svc)

status:
	@echo "=== All Containers (across all compose projects) ==="
	@docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
	@echo ""
	@echo "=== Resource Usage ==="
	@docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"

# === Database ===
backup:
	@bash scripts/backup.sh

db-shell:
	docker compose exec postgres psql -U postgres

# === Cross-Repo Deploy ===
deploy-all:
	@bash scripts/deploy-all.sh

# === Health Check ===
health:
	@echo "chat-api:" && curl -sf http://localhost:8000/health/ready | jq . || echo "DOWN"
	@echo "rag-api:" && curl -sf http://localhost:8001/health/ready | jq . || echo "DOWN"
```

### chat-api/Makefile (same pattern for rag-service)

```makefile
# chat-api/Makefile

.PHONY: up down logs deploy test

up:
	docker compose up -d

down:
	docker compose down

logs:
	docker compose logs -f --tail=100 $(svc)

deploy:
	git pull
	docker compose up -d --build --remove-orphans

test:
	docker compose exec chat-api pytest tests/

shell:
	docker compose exec chat-api sh
```

**Usage**: `make deploy-all` (from infra repo), `make deploy` (from any app repo), `make status`, `make backup`.

---

## Backup Strategy (Automated)

```bash
#!/bin/bash
# infra-platform/scripts/backup.sh
# Run via: crontab -e → 0 3 * * * /path/to/infra-platform/scripts/backup.sh

set -euo pipefail

BACKUP_DIR="/backups/postgres"
RETENTION_DAYS=7
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$BACKUP_DIR"

# Dump all databases
INFRA_DIR="$(dirname "$(dirname "$(realpath "$0")")")" 
cd "$INFRA_DIR" && docker compose exec -T postgres pg_dumpall -U postgres \
  | gzip > "$BACKUP_DIR/full_${TIMESTAMP}.sql.gz"

# Prune old backups
find "$BACKUP_DIR" -name "*.sql.gz" -mtime +$RETENTION_DAYS -delete

echo "[$(date)] Backup complete: full_${TIMESTAMP}.sql.gz"
echo "[$(date)] Backups retained: $(ls -1 $BACKUP_DIR/*.sql.gz | wc -l)"
```

> [!TIP]
> Add a weekly `rclone sync /backups s3://your-bucket/backups` for off-site copies (~$0.50/mo for small datasets on Backblaze B2).

---

## Port Map (Solo)

| Service | Internal Port | Host Port | Network | Access | You Use For |
|---|---|---|---|---|---|
| nginx | 80 / 443 | **80 / 443** | frontend-net, internal-net | Public | — |
| postgres | 5432 | — | internal-net | Internal only | — |
| redis | 6379 | — | internal-net | Internal only | — |
| chat-api | 8000 | — | frontend-net, internal-net | Via NGINX | — |
| chat-worker | — | — | internal-net | Internal only | — |
| rag-api | 8001 | — | frontend-net, internal-net | Via NGINX | — |
| prometheus | 9090 | **9090** | internal-net | Tailscale / IP allowlist | Metrics (via Grafana) |
| grafana | 3000 | **3000** | internal-net | Tailscale / IP allowlist | **Logs + Metrics** |
| loki | 3100 | — | internal-net | Internal only | Logs (via Grafana) |
| jaeger | 16686 / 4318 | **16686** | internal-net | Tailscale / IP allowlist | **Traces** |

> [!NOTE]
> **"Tailscale / IP allowlist"** = bind to `127.0.0.1` on the host and access via Tailscale VPN (free for personal use, 2-minute setup). Or use `ufw allow from YOUR_IP to any port 3000`.

---

## What You Dropped and When to Add It Back

| Dropped Component | Add Back When... | Effort |
|---|---|---|
| **Promtail** container | Loki Docker log driver gives you issues or you need advanced pipeline stages | 30 min |
| **Alertmanager** | You need PagerDuty escalation policies or on-call rotation | 1 hour |
| **node-exporter** | You're on bare metal and need CPU/disk/network host metrics | 15 min |
| **cAdvisor** | You need per-container CPU/memory metrics in Prometheus (vs `docker stats`) | 15 min |
| **postgres-exporter** | PG query performance becomes a bottleneck (>100 RPS or slow queries) | 30 min |
| **redis-exporter** | Redis memory/eviction issues appear | 15 min |
| **3rd & 4th network** | You hire someone who shouldn't access all services | 30 min |
| **Monorepo merge** | If cross-repo coordination becomes painful (unlikely for solo) | 2 hours |
| **Docker secrets** | You move to Docker Swarm or need rotation without restart | 1 hour |
| **mTLS** | Traffic crosses a network boundary (multi-host or public cloud VPC) | 4 hours |
| **Read-only FS** | After a security audit or compliance requirement | 1 hour |

---

## Trade-offs: Solo vs. Team vs. K8s

| Decision | Solo (this doc) | Team (v2) | K8s / Scale |
|---|---|---|---|
| Network model | 2 networks | 4 networks | NetworkPolicies + service mesh |
| Repos | 3 repos + deploy script | 3 repos + contracts | Monorepo or per-service with CI orchestration |
| Alerting | Grafana built-in | Alertmanager | Alertmanager HA + PagerDuty |
| Log collection | Loki Docker driver | Promtail sidecar | Fluentbit DaemonSet → Loki |
| Host metrics | `docker stats` / skip | node-exporter + cAdvisor | Prometheus Operator + kube-state-metrics |
| Secrets | `.env` + `chmod 600` | Docker secrets | Vault + K8s CSI driver |
| Management UIs | Direct host ports + Tailscale | SSH tunnels | Ingress with OIDC auth |
| Backups | Cron + `pg_dumpall` | Cron + offsite | PG operator with WAL archiving |
| Deploy | `make deploy-all` (orchestration script) | Per-repo CI/CD | ArgoCD / Flux GitOps |

---

## Daily Ops Checklist (< 5 minutes)

```
☐ make status         → all containers green? (from infra repo)
☐ Grafana :3000       → any firing alerts? check logs + metrics
☐ Jaeger :16686       → any slow traces or errors? (spot check)
☐ make backup         → ran today? (check cron log)
☐ df -h               → disk below 80%?
```

That's it. If all four pass, go build product.

---

## Summary: v2 → Solo

| Area | v2 (Team) | Solo |
|---|---|---|
| **Containers** | 16 | **10** |
| **Networks** | 4 | **2** |
| **Git repos** | 3 | **3** (same, but lighter ceremony) |
| **Config files to maintain** | ~20+ with contracts | **~12 total across repos** |
| **Daily ops time** | Team rotations | **< 5 min checklist** |
| **RAM footprint** | ~6–8 GB | **~3–4 GB** |
| **Alerting** | Alertmanager + runbooks | **Grafana → Telegram** |
| **Deployment** | 3 separate CI/CD pipelines | **`make deploy-all`** |
| **Security model** | Defense in depth | **Minimum viable security** |
| **Upgrade path** | — | **Every cut has a documented trigger to add back** |
