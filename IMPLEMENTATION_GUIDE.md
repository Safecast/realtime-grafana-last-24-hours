# DuckLake Implementation Guide

## Overview

This guide walks you through migrating from single-file DuckDB to DuckLake for true concurrent read/write access.

**Problem Solved:** Grafana and your data collection script can now run simultaneously without locking errors!

---

## Implementation Steps

### Phase 1: Test Locally First

#### Step 1: Backup Everything

```bash
cd ~/Documents/realtime-grafana-last-24-hours

# Create backup of current script
cp devices-last-24-hours.sh devices-last-24-hours-old.sh.backup

# Verify new files are ready
ls -lh migrate-to-ducklake.sh devices-last-24-hours-ducklake.sh
```

#### Step 2: Run Migration on Local Machine

```bash
# Run migration script
./migrate-to-ducklake.sh
```

**Expected Output:**
```
==========================================
Migrating to DuckLake
==========================================

✅ Found DuckDB at: /home/rob/.local/bin/duckdb
📦 Step 1: Creating backup...
✅ Backup created: /var/lib/grafana/data/devices.duckdb.backup_20251106_150000
📤 Step 2: Exporting existing data to Parquet...
✅ Exported 1762 rows to Parquet
🦆 Step 3: Creating DuckLake catalog and structure...
✅ DuckLake catalog created: /var/lib/grafana/data/ducklake_catalog.db
✅ DuckLake data directory: /var/lib/grafana/data/ducklake_data/
📥 Step 4: Importing data into DuckLake...
✅ Imported 1762 rows into DuckLake
🔐 Step 5: Setting permissions...
✅ Permissions set for grafana:grafana
🧪 Step 6: Testing DuckLake access...
[Statistics displayed]
✅ Migration Complete!
```

#### Step 3: Update Grafana Datasource (Local)

1. Open Grafana: http://localhost:3000
2. Go to: **Configuration** → **Data Sources** → **motherduck-duckdb-datasource**
3. Update settings:

   **Before:**
   ```
   Database name: /var/lib/grafana/data/devices.duckdb
   Init SQL: (empty or existing)
   ```

   **After:**
   ```
   Database name: ducklake:/var/lib/grafana/data/ducklake_catalog.db
   Init SQL:
   INSTALL ducklake;
   LOAD ducklake;
   ATTACH 'ducklake:/var/lib/grafana/data/ducklake_catalog.db' AS safecast
       (DATA_PATH '/var/lib/grafana/data/ducklake_data/');
   USE safecast;
   ```

4. Click **Save & Test**
5. Should see: ✅ "Successfully connected to database"

#### Step 4: Test Data Collection Script (Local)

```bash
# Test the new DuckLake script
./devices-last-24-hours-ducklake.sh
```

**Expected Output:**
```
[Thu Nov  6 15:30:00 UTC 2025] Fetching device data and inserting into DuckLake...
[Thu Nov  6 15:30:00 UTC 2025] Found DuckDB binary at: /home/rob/.local/bin/duckdb
[Thu Nov  6 15:30:00 UTC 2025] Using DuckDB version: 1.4.1
[Thu Nov  6 15:30:00 UTC 2025] Fetching and processing data...
[Thu Nov  6 15:30:05 UTC 2025] Inserting data into DuckLake (concurrent write)...
[Thu Nov  6 15:30:06 UTC 2025] Data inserted into DuckLake successfully!
============================================
Data pipeline completed successfully!
Total measurements in DuckLake: 1774
============================================
```

#### Step 5: Test Concurrent Access (Local)

**Terminal 1:**
```bash
# Open Grafana dashboard in browser: http://localhost:3000
# Keep dashboard open and refreshing
```

**Terminal 2:**
```bash
# While Grafana is actively displaying data, run:
./devices-last-24-hours-ducklake.sh
```

**Expected Result:** ✅ Script completes successfully without any locking errors!

Verify in Terminal 1 that Grafana dashboard continues to work and updates with new data.

---

### Phase 2: Deploy to Server

Once local testing is successful, deploy to production server.

#### Step 1: Upload New Files to Server

```bash
# From your local machine
scp migrate-to-ducklake.sh devices-last-24-hours-ducklake.sh \
    root@grafana.safecast.jp:/home/grafana.safecast.jp/public_html/

# Make executable
ssh root@grafana.safecast.jp "chmod +x /home/grafana.safecast.jp/public_html/migrate-to-ducklake.sh /home/grafana.safecast.jp/public_html/devices-last-24-hours-ducklake.sh"
```

#### Step 2: Stop Grafana (Prevent Access During Migration)

```bash
ssh root@grafana.safecast.jp
cd /home/grafana.safecast.jp/public_html

# Stop Grafana temporarily
sudo systemctl stop grafana-server
```

#### Step 3: Run Migration on Server

```bash
# Run migration
./migrate-to-ducklake.sh
```

#### Step 4: Update Grafana Datasource (Server)

1. Start Grafana:
   ```bash
   sudo systemctl start grafana-server
   ```

2. Open Grafana: https://grafana.safecast.jp
3. Go to: **Configuration** → **Data Sources** → **motherduck-duckdb-datasource**
4. Update settings (same as local):

   ```
   Database name: ducklake:/var/lib/grafana/data/ducklake_catalog.db

   Init SQL:
   INSTALL ducklake;
   LOAD ducklake;
   ATTACH 'ducklake:/var/lib/grafana/data/ducklake_catalog.db' AS safecast
       (DATA_PATH '/var/lib/grafana/data/ducklake_data/');
   USE safecast;
   ```

5. Click **Save & Test**

#### Step 5: Test on Server

```bash
# Test new script
./devices-last-24-hours-ducklake.sh
```

#### Step 6: Test Concurrent Access (Server)

1. Open Grafana dashboard: https://grafana.safecast.jp
2. While dashboard is active, run:
   ```bash
   ./devices-last-24-hours-ducklake.sh
   ```

**Expected Result:** ✅ Both work simultaneously!

#### Step 7: Update Cron Job (Server)

```bash
# Edit crontab
crontab -e

# Update the line from:
*/15 * * * * cd /home/grafana.safecast.jp/public_html && ./devices-last-24-hours.sh

# To:
*/15 * * * * cd /home/grafana.safecast.jp/public_html && ./devices-last-24-hours-ducklake.sh

# Save and exit
```

---

## Verification Checklist

After deployment, verify everything works:

- [ ] Migration completed without errors
- [ ] Grafana shows correct row count
- [ ] Grafana dashboards display data correctly
- [ ] Data collection script runs successfully
- [ ] Script and Grafana work simultaneously (no locking errors)
- [ ] Cron job updated
- [ ] Test concurrent access: open dashboard + run script

---

## File Locations

### Local Machine:
```
/var/lib/grafana/data/
├── devices.duckdb                          # OLD (kept as backup)
├── devices.duckdb.backup_YYYYMMDD_HHMMSS  # Automatic backup
├── ducklake_catalog.db                     # NEW: SQLite catalog
├── ducklake_catalog.db.wal                 # NEW: WAL file
└── ducklake_data/                          # NEW: Parquet data files
    └── [generated parquet files]
```

### Server:
```
/home/grafana.safecast.jp/public_html/
├── devices-last-24-hours.sh                # OLD script (keep as backup)
├── devices-last-24-hours-ducklake.sh       # NEW script
└── migrate-to-ducklake.sh                  # Migration script

/var/lib/grafana/data/
├── devices.duckdb                          # OLD (kept as backup)
├── ducklake_catalog.db                     # NEW: SQLite catalog
└── ducklake_data/                          # NEW: Parquet data files
```

---

## Troubleshooting

### Error: "Extension ducklake not found"

DuckDB version too old. Upgrade to DuckDB 1.4.0+:
```bash
# Check version
duckdb -version

# If < 1.4.0, upgrade (see DuckDB installation guide)
```

### Error: "Permission denied" on catalog

Fix permissions:
```bash
sudo chown grafana:grafana /var/lib/grafana/data/ducklake_catalog.db*
sudo chmod 664 /var/lib/grafana/data/ducklake_catalog.db*
```

### Error: "Table measurements does not exist"

Re-run migration:
```bash
./migrate-to-ducklake.sh
```

### Grafana shows no data

1. Check Init SQL is correct
2. Verify database path uses `ducklake:` prefix
3. Check Grafana logs:
   ```bash
   sudo journalctl -u grafana-server -f | grep -i duck
   ```

### Script still shows locking errors

1. Verify you're running the **new** script: `devices-last-24-hours-ducklake.sh`
2. Check that Grafana datasource is using DuckLake path (with `ducklake:` prefix)
3. Verify catalog file exists:
   ```bash
   ls -la /var/lib/grafana/data/ducklake_catalog.db*
   ```

---

## Rollback Procedure

If you need to revert to the old setup:

```bash
# Stop Grafana
sudo systemctl stop grafana-server

# Restore old database (if needed)
sudo cp /var/lib/grafana/data/devices.duckdb.backup_* \
     /var/lib/grafana/data/devices.duckdb

# Revert Grafana datasource settings
# Database name: /var/lib/grafana/data/devices.duckdb
# Init SQL: (clear)

# Start Grafana
sudo systemctl start grafana-server

# Use old script
cp devices-last-24-hours-old.sh.backup devices-last-24-hours.sh

# Update cron to old script
crontab -e
```

---

## Benefits Achieved

After implementing DuckLake:

✅ **True concurrent access** - No more locking errors
✅ **No retry logic needed** - Direct writes always work
✅ **Time travel queries** - Query historical snapshots
✅ **Better scalability** - Parquet format optimized for analytics
✅ **ACID guarantees** - No data corruption risk
✅ **Same Grafana plugin** - No plugin modification needed

---

## Next Steps After Implementation

1. Monitor for first 24 hours to ensure stability
2. Remove old backup files after confirming everything works:
   ```bash
   # After 1 week of successful operation
   sudo rm /var/lib/grafana/data/devices.duckdb.backup_*
   ```
3. Set up DuckLake maintenance (optional):
   ```bash
   # Monthly cleanup of old snapshots
   # Add to cron:
   0 2 1 * * duckdb -c "ATTACH 'ducklake:/var/lib/grafana/data/ducklake_catalog.db' AS safecast; USE safecast; CALL ducklake_expire_snapshots(30);"
   ```

---

Ready to proceed? Start with **Phase 1: Test Locally First**
