#!/bin/bash
# Check if all infrastructure components are healthy

set -euo pipefail

echo "=== Health Checking Infrastructure Layer ==="
INFRA_DIR="$(dirname "$(dirname "$(realpath "$0")")")" 
cd "$INFRA_DIR"

# 1. Check if all containers are running
echo "Checking container statuses..."
docker compose ps || { echo "Docker compose is not running here."; exit 1; }

# 2. Check NGINX
echo -n "Checking NGINX: "
if curl -s http://localhost/nginx-health | grep -q 'healthy'; then
    echo "✅ UP"
else
    echo "❌ DOWN"
fi

# 3. Check Grafana
echo -n "Checking Grafana: "
if curl -s http://127.0.0.1:3000/api/health | grep -q 'ok'; then
    echo "✅ UP"
else
    echo "❌ DOWN"
fi

# 4. Check Prometheus
echo -n "Checking Prometheus: "
if curl -s http://127.0.0.1:9090/-/healthy | grep -q 'Prometheus Server is Healthy'; then
    echo "✅ UP"
else
    echo "❌ DOWN"
fi

# 5. Check Jaeger UI
echo -n "Checking Jaeger UI: "
if curl -s -I http://127.0.0.1:16686 | head -n 1 | grep -q '200 OK'; then
    echo "✅ UP"
else
    echo "❌ DOWN"
fi

# 6. Check Postgres
echo -n "Checking Postgres: "
if docker compose exec -T postgres pg_isready -U admin -q; then
    echo "✅ UP"
else
    echo "❌ DOWN"
fi

# 7. Check Redis
echo -n "Checking Redis: "
if docker compose exec -T redis redis-cli ping | grep -q "PONG"; then
    echo "✅ UP"
else
    echo "❌ DOWN"
fi

echo "=== All checks completed ==="
