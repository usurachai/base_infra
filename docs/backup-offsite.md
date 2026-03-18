# Offsite Backup Setup

The backup script (`scripts/backup.sh`) supports automatic offsite sync via [rclone](https://rclone.org). When rclone is installed and a remote named `backup` is configured, each backup is automatically synced offsite after local integrity verification.

## Supported Providers

rclone supports 70+ cloud providers. Common choices for a solo-founder stack:

| Provider | Notes |
|----------|-------|
| Cloudflare R2 | Free egress, S3-compatible |
| Backblaze B2 | Very cheap storage |
| AWS S3 | Standard, well-documented |
| Google Cloud Storage | Good if already on GCP |

## Setup

### 1. Install rclone

```bash
curl https://rclone.org/install.sh | sudo bash
```

### 2. Configure a remote named `backup`

```bash
rclone config
# Follow the interactive prompts
# Name the remote exactly: backup
```

### 3. Test the connection

```bash
rclone lsd backup:
```

### 4. Verify auto-sync is working

```bash
make backup
# Look for "Syncing backup to offsite storage..." in the output
```

## Manual Sync

To manually sync all existing local backups to offsite:

```bash
rclone sync /backups/postgres backup:postgres-backups/
```

## Notes

- The script will warn (but not fail) if rclone is unavailable — local backups are always written first
- Integrity is verified with `gzip -t` before the offsite sync runs
- The backup script exits non-zero on corrupt files, making it safe to alert on cron failures
