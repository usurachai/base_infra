# base_infra (Infrastructure Platform)

[![GitHub Repository](https://img.shields.io/badge/GitHub-usurachai/base_infra-blue?logo=github)](https://github.com/usurachai/base_infra)

This repository contains the foundational infrastructure layer for the solo-founder architecture. It provides shared Docker networks, data stores, a reverse proxy, a full observability stack, and alerting. Application repositories join these networks as `external: true`.

---

## Architecture Overview

**14 Containers across two tiers:**

### Core Services
| Container | Image | Role |
| --- | --- | --- |
| `nginx` | `openresty/openresty:alpine` | Reverse proxy with Lua body masking, rate limiting, structured JSON logging |
| `postgres` | `pgvector/pgvector:pg16` | Primary DB with `pgvector` extension and per-app schema isolation |
| `redis` | `redis:7-alpine` | Shared cache and task queue with AOF persistence |

### Observability
| Container | Image | Role |
| --- | --- | --- |
| `prometheus` | `prom/prometheus:v2.45.0` | Metric scraping and TSDB (15-day retention) |
| `loki` | `grafana/loki:3.0.0` | Log aggregation (7-day retention) |
| `promtail` | `grafana/promtail:3.0.0` | Docker socket log collector → Loki |
| `grafana` | `grafana/grafana:10.4.1` | Dashboarding (metrics + logs) |
| `jaeger` | `jaegertracing/all-in-one:1.56` | Distributed tracing via OTLP, Badger persistent storage |
| `alertmanager` | `prom/alertmanager:v0.27.0` | Alert routing (Prometheus → Slack / email) |

### Exporters
| Container | Image | Role |
| --- | --- | --- |
| `nginx-exporter` | `nginx/nginx-prometheus-exporter:1.1.0` | NGINX stub status → Prometheus |
| `postgres-exporter` | `prometheuscommunity/postgres-exporter:v0.15.0` | PostgreSQL metrics → Prometheus |
| `redis-exporter` | `oliver006/redis_exporter:v1.62.0` | Redis metrics → Prometheus |

### Networks

1. `frontend-net` — NGINX only. Entry point for all inbound traffic.
2. `internal-net` — Private. All services (apps, databases, observability) communicate here.

App repos declare both networks as `external: true` in their own `docker-compose.yml`. NGINX proxies to them by container hostname.

---

## Quick Start

1. **Clone this repo**
2. **Configure environment variables**:
   ```bash
   cp .env.example .env
   # Edit .env — change all passwords before starting
   ```
3. **Start the infrastructure**:
   ```bash
   make up
   ```
4. **Verify health**:
   ```bash
   make health
   ```

> **Note:** NGINX will return `502 Bad Gateway` on `/api/*` routes until app containers are running and joined to the networks.

---

## Port Map

| Service | Host Binding | Access Method |
| --- | --- | --- |
| NGINX | `:80`, `:443` | Public (your domain / IP) |
| Grafana | `127.0.0.1:3000` | SSH tunnel / Tailscale |
| Prometheus | `127.0.0.1:9090` | SSH tunnel / Tailscale |
| Jaeger UI | `127.0.0.1:16686` | SSH tunnel / Tailscale |
| Alertmanager | `127.0.0.1:9093` | SSH tunnel / Tailscale |
| PostgreSQL | `127.0.0.1:5432` | `make db-shell` or tunnel |

*Redis, Loki, Promtail, and exporters are not exposed to the host by design.*

---

## PostgreSQL Role Isolation

Each app gets a dedicated schema and role within the shared `meowdb` database:

| Role | Schema | App |
| --- | --- | --- |
| `zenconnect_app` | `zenconnect` | zendesk-agent-api |
| `meowrag_app` | `meowrag` | rag-api |

Roles have no `CREATEDB` and are scoped to their own schema via `ALTER ROLE ... SET search_path`. The `public` schema has `CREATE` revoked.

---

## Observability Pipeline

```
Docker containers
   └── Promtail (Docker socket)
           └── Loki ──────────────┐
                                  ▼
Prometheus ◄── exporters     Grafana (dashboards)
   └── alerting rules
           └── Alertmanager (Slack / email)

App services ──OTLP──► Jaeger (Badger storage)
```

---

## Backups

`make backup` (or cron at `0 3 * * *`) runs `scripts/backup.sh`:

1. `pg_dumpall` → gzipped to `/backups/postgres/`
2. Integrity check via `gzip -t`
3. Offsite sync via `rclone copy` to `backup:postgres-backups/` (if rclone is configured)
4. Local retention: 7 days

See [`docs/backup-offsite.md`](./docs/backup-offsite.md) for rclone setup.

---

## Daily Operations

```bash
make up              # Start all services
make down            # Stop all services
make status          # View container status and resource usage
make logs svc=nginx  # Tail logs for a specific service
make health          # Run healthchecks against all components
make backup          # Manually trigger a PostgreSQL backup
make db-shell        # Open PostgreSQL interactive shell
```

---

## Adding a New App

1. In your app's `docker-compose.yml`, declare the networks as external:
   ```yaml
   networks:
     frontend-net:
       external: true
     internal-net:
       external: true
   ```
2. Add an NGINX `location` block in `nginx/conf.d/routes.conf` pointing to your container hostname
3. Add a Prometheus scrape job in `prometheus/prometheus.yml` if your app exposes `/metrics`
4. Add a role and schema to `postgres/init.sh` if your app uses PostgreSQL

See [Infrastructure Design_solo.md](./Infrastructure%20Design_solo.md) for deeper architectural reasoning.
