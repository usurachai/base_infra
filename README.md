# base_infra (Infrastructure Platform)

This repository contains the foundational infrastructure layer for the solo-founder architecture. It creates shared Docker networks, data stores, a reverse proxy, and an observability stack. Application repositories like `chat-api` and `rag-service` join these networks as `external: true`.

## Architecture Overview

**Core Services (8 Containers)**:
- **NGINX**: Reverse proxy mapping `/api/*` to backend microservices
- **PostgreSQL 16**: Primary DB with `pgvector` and role-based isolation (`chat_app`, `rag_app`)
- **Redis 7**: Shared cache and task queue (requires auth)
- **Prometheus**: Metric scraping and TSDB
- **Loki**: Log aggregator (single process mode)
- **Promtail**: Scrapes all Docker logs via socket and pushes to Loki
- **Grafana**: Dashboarding (logs + metrics)
- **Jaeger**: OpenTelemetry distributed tracing

### Networks

1. `frontend-net`: NGINX reverse-proxying down to app backends
2. `internal-net`: Secure lane for apps to reach PostgreSQL/Redis/Observability tools

---

## Quick Start

1. **Clone this repo**.
2. **Configure environment variables**:
   ```bash
   cp .env.example .env
   # Edit .env and change all passwords!
   ```
3. **Start the infrastructure**:
   ```bash
   make up
   ```
4. **Verify Health**:
   ```bash
   make health
   ```

*Note: Initially, NGINX may return `502 Bad Gateway` on `/api/chat/` until your app repositories are also booted and joined to the networks.*

---

## Port Map

| Service | Host Binding | Access Method |
| --- | --- | --- |
| NGINX | `:80`, `:443` | Public (Your Domain / IP) |
| Grafana | `127.0.0.1:3000` | SSH Tunnel / Tailscale |
| Prometheus | `127.0.0.1:9090` | SSH Tunnel / Tailscale |
| Jaeger UI | `127.0.0.1:16686`| SSH Tunnel / Tailscale |

*PostgreSQL, Redis, Loki, and Promtail are **not** exposed to the host by design. Connect via `docker compose exec` or a container on `internal-net`.*

---

## Promtail Log Collection

This setup uses **Promtail** as a centralized log collector for Docker:
- Automatically mounts `/var/run/docker.sock` to discover running containers across **all** compose projects.
- Pulls stdout/stderr and enriches logs with compose labels (e.g. `compose_project`, `compose_service`).
- Sends logs to Loki.
- Unlike the Docker log driver plugin, this does **not** require modifying `/etc/docker/daemon.json` on the host machine.

---

## Daily Operations

Use the included `Makefile` to manage the infrastructure:

```bash
make status  # View status and resource consumption
make logs    # Tail logs of all infra containers
make backup  # Manually run a PostgreSQL pg_dumpall
make health  # Run the ping/HTTP healthchecks
```

See [Infrastructure Design_solo.md](./Infrastructure%20Design_solo.md) for deeper architectural reasoning.
