# base_infra/Makefile — infrastructure operations

.PHONY: up down status backup health db-shell logs

# === Infrastructure ===
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
	docker compose exec postgres psql -U admin

# === Health Check ===
health:
	@bash scripts/healthcheck.sh
