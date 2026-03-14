#!/bin/bash
# infra-platform/scripts/backup.sh
# Run via: crontab -e → 0 3 * * * /path/to/base_infra/scripts/backup.sh

set -euo pipefail

BACKUP_DIR="/backups/postgres"
RETENTION_DAYS=7
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$BACKUP_DIR"

# Dump all databases
# Note: Ensure the POSTGRES_PASSWORD environment variable is exposed/accessible if run via cron, 
# or use the docker exec approach which does not prompt for password if executed from compose
INFRA_DIR="$(dirname "$(dirname "$(realpath "$0")")")" 
cd "$INFRA_DIR" && docker compose exec -T postgres pg_dumpall -U admin \
  | gzip > "$BACKUP_DIR/full_${TIMESTAMP}.sql.gz"

# Prune old backups
find "$BACKUP_DIR" -name "*.sql.gz" -mtime +$RETENTION_DAYS -delete

echo "[$(date)] Backup complete: full_${TIMESTAMP}.sql.gz"
echo "[$(date)] Backups retained: $(find "$BACKUP_DIR" -name "*.sql.gz" | wc -l)"
