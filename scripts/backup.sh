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

# Verify backup integrity
echo "[$(date)] Verifying backup integrity..."
if ! gzip -t "$BACKUP_DIR/full_${TIMESTAMP}.sql.gz"; then
  echo "[$(date)] ERROR: Backup file is corrupt or incomplete!" >&2
  exit 1
fi
echo "[$(date)] Integrity check passed."

# Offsite sync (requires rclone configured with a remote named 'backup')
# See docs/backup-offsite.md for setup instructions
if command -v rclone &>/dev/null && rclone listremotes | grep -q "^backup:"; then
  echo "[$(date)] Syncing backup to offsite storage..."
  if rclone copy "$BACKUP_DIR/full_${TIMESTAMP}.sql.gz" backup:postgres-backups/; then
    echo "[$(date)] Offsite sync complete."
  else
    echo "[$(date)] WARNING: Offsite sync failed — local backup still intact." >&2
  fi
else
  echo "[$(date)] WARNING: rclone not configured — skipping offsite sync. See docs/backup-offsite.md to set up." >&2
fi

# Prune old backups
find "$BACKUP_DIR" -name "*.sql.gz" -mtime +$RETENTION_DAYS -delete

echo "[$(date)] Backup complete: full_${TIMESTAMP}.sql.gz"
echo "[$(date)] Backups retained: $(find "$BACKUP_DIR" -name "*.sql.gz" | wc -l)"
