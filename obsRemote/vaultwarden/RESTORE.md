# Vaultwarden Restore Procedure

## Quick Restore

```bash
# Stop vaultwarden
cd /root/Orchestration/obsRemote
source script/sourceEnv.sh
docker compose -f run_obsidian_remote.yml stop vaultwarden

# Backup current data (just in case)
mv vaultwarden/vw-data vaultwarden/vw-data.old

# Extract backup (replace YYYYMMDD_HHMMSS with actual timestamp)
tar -xzf /var/backups/vaultwarden/vaultwarden_backup_YYYYMMDD_HHMMSS.tar.gz

# Fix permissions
chown -R 1000:1000 vaultwarden/vw-data

# Start vaultwarden
docker compose -f run_obsidian_remote.yml start vaultwarden

# Verify data is intact
./script/see-logs.sh vaultwarden
```

## List Available Backups

```bash
ls -lh /var/backups/vaultwarden/
```
