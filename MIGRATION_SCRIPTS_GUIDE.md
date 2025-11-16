# DuckLake Migration Scripts Guide

## Available Scripts

### 1. `migrate-to-ducklake.sh` (Auto-selector)
**Purpose:** Automatically detects your environment and runs the appropriate migration script.

**Usage:**
```bash
./migrate-to-ducklake.sh
```

**Detection Logic:**
- Checks hostname
- If contains "rob" → runs **local** version
- If contains "safecast" or "vps-01" → runs **server** version
- Otherwise → prompts you to run manually

---

### 2. `migrate-to-ducklake-local.sh` (Local Machine)
**Purpose:** Migration script specifically for your local machine (rob-GS66-Stealth-10UG)

**Features:**
- Uses local paths and configurations
- Adds user to grafana group if needed
- References localhost Grafana (http://localhost:3000)
- Uses `sudo` for permission operations

**When to use:**
- Testing DuckLake on your local machine
- Before deploying to server

---

### 3. `migrate-to-ducklake-server.sh` (Production Server)
**Purpose:** Migration script specifically for grafana.safecast.jp server

**Features:**
- Checks for "/root/.local/bin/duckdb" first (server location)
- Includes safety check to confirm it's the server
- References server Grafana (https://grafana.safecast.jp)
- Assumes root user (no sudo needed)
- Includes cron job update instructions

**When to use:**
- Deploying to production server
- After successful local testing

---

## Key Differences

| Feature | Local Script | Server Script |
|---------|-------------|---------------|
| **DuckDB Location** | `$HOME/.local/bin/duckdb` | `/root/.local/bin/duckdb` |
| **User Permissions** | Uses `sudo` | Assumes root |
| **Safety Check** | None | Confirms hostname |
| **Group Addition** | Adds user to grafana group | Not needed (root) |
| **Grafana URL** | localhost:3000 | grafana.safecast.jp |
| **Cron Instructions** | No | Yes |

---

## Usage Workflow

### Quick Start (Recommended)

Just run the auto-selector:
```bash
cd ~/Documents/realtime-grafana-last-24-hours
./migrate-to-ducklake.sh
```

It will automatically:
1. Detect your environment
2. Run the appropriate script
3. Show environment-specific instructions

---

### Manual Selection

If you prefer to run specific scripts:

**On Local Machine:**
```bash
./migrate-to-ducklake-local.sh
```

**On Server:**
```bash
# First, upload script to server
scp migrate-to-ducklake-server.sh root@grafana.safecast.jp:/home/grafana.safecast.jp/public_html/

# SSH to server
ssh root@grafana.safecast.jp
cd /home/grafana.safecast.jp/public_html

# Make executable
chmod +x migrate-to-ducklake-server.sh

# Run migration
./migrate-to-ducklake-server.sh
```

---

## What Each Script Does

### Phase 1: Backup (Both Scripts)
- Creates timestamped backup of existing database
- Location: `devices.duckdb.backup_YYYYMMDD_HHMMSS`

### Phase 2: Export (Both Scripts)
- Exports current data to Parquet format
- Temporary file: `measurements_export.parquet`

### Phase 3: Create DuckLake (Both Scripts)
- Creates SQLite catalog: `ducklake_catalog.db`
- Creates data directory: `ducklake_data/`
- Creates measurements table (without PRIMARY KEY)

### Phase 4: Import (Both Scripts)
- Imports data from Parquet into DuckLake
- Verifies row count matches export

### Phase 5: Permissions (Different)
- **Local:** Uses `sudo`, adds user to grafana group
- **Server:** Direct chown (running as root)

### Phase 6: Test (Both Scripts)
- Runs test query to verify DuckLake works
- Shows statistics (count, date range, etc.)

---

## After Migration

### Both Environments

1. **Restart Grafana:**
   ```bash
   sudo systemctl restart grafana-server
   ```

2. **Update Grafana Datasource:**
   - Database path: `ducklake:/var/lib/grafana/data/ducklake_catalog.db`
   - Init SQL:
     ```sql
     INSTALL ducklake; LOAD ducklake;
     ATTACH 'ducklake:/var/lib/grafana/data/ducklake_catalog.db' AS safecast
         (DATA_PATH '/var/lib/grafana/data/ducklake_data/');
     USE safecast;
     ```

3. **Test new data collection script:**
   ```bash
   ./devices-last-24-hours-ducklake.sh
   ```

4. **Test concurrent access:**
   - Open Grafana dashboard
   - Run data collection script
   - Both should work simultaneously!

### Server Only

5. **Update cron job:**
   ```bash
   crontab -e
   # Change from:
   */15 * * * * cd /home/grafana.safecast.jp/public_html && ./devices-last-24-hours.sh
   # To:
   */15 * * * * cd /home/grafana.safecast.jp/public_html && ./devices-last-24-hours-ducklake.sh
   ```

---

## Rollback

If you need to revert:

**Local:**
```bash
sudo systemctl stop grafana-server
sudo cp /var/lib/grafana/data/devices.duckdb.backup_* \
     /var/lib/grafana/data/devices.duckdb
# Revert Grafana datasource settings
sudo systemctl start grafana-server
```

**Server:**
```bash
sudo systemctl stop grafana-server
cp /var/lib/grafana/data/devices.duckdb.backup_* \
   /var/lib/grafana/data/devices.duckdb
# Revert Grafana datasource settings
sudo systemctl start grafana-server
```

---

## Troubleshooting

### "DuckDB binary not found"

**Local:**
- Check: `ls -la ~/.local/bin/duckdb`
- Install if missing: https://duckdb.org/docs/installation/

**Server:**
- Check: `ls -la /root/.local/bin/duckdb`
- Install if missing

### "Permission denied"

**Local:**
- Make sure you're in the grafana group: `groups`
- If not, log out and log back in
- Or run with sudo: `sudo ./migrate-to-ducklake-local.sh`

**Server:**
- Make sure you're running as root: `whoami`
- Or use sudo: `sudo ./migrate-to-ducklake-server.sh`

### "Wrong environment detected"

If the auto-selector chooses wrong:
```bash
# Run the correct script manually
./migrate-to-ducklake-local.sh   # For local
./migrate-to-ducklake-server.sh  # For server
```

---

## Summary

- 📁 **3 scripts**: Auto-selector + Local + Server
- 🎯 **Simple usage**: Just run `./migrate-to-ducklake.sh`
- 🔒 **Safe**: Creates backups before changes
- ✅ **Tested**: Both versions handle their environments correctly
- 🔄 **Reversible**: Backups allow easy rollback

Choose the workflow that works for you - auto-detection or manual selection!
