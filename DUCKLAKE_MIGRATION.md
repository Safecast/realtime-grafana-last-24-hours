# Migrating to DuckLake for Concurrent Access

## Why DuckLake?

DuckLake enables **multiple DuckDB instances to read and write concurrently** - solving your locking problem!

### Architecture Comparison

**Current Setup (Single File):**
```
devices.duckdb (locked by Grafana)
    ↓
❌ Script can't write when Grafana is reading
```

**DuckLake Setup:**
```
SQLite Catalog (metadata coordination)
    ↓ coordinates ↓
Grafana reads    +    Script writes    (both work concurrently!)
    ↓                      ↓
Parquet files (shared data storage)
```

---

## Quick Start: Automated Migration

We've created automated migration scripts that handle everything for you!

### Option 1: Auto-Detect Environment (Recommended)

```bash
cd ~/Documents/realtime-grafana-last-24-hours
./migrate-to-ducklake.sh
```

This script will:
- ✅ Detect if you're on local machine or server
- ✅ Run the appropriate migration script
- ✅ Handle all steps automatically

### Option 2: Run Specific Script

**Local Machine:**
```bash
./migrate-to-ducklake-local.sh
```

**Server:**
```bash
./migrate-to-ducklake-server.sh
```

### What the Migration Scripts Do

1. **📦 Backup** - Creates timestamped backup of existing database
2. **📤 Export** - Exports current data to Parquet format
3. **🦆 Create DuckLake** - Sets up SQLite catalog and data directory
4. **📥 Import** - Loads existing data into DuckLake
5. **🔐 Permissions** - Sets proper ownership and permissions
6. **🧪 Test** - Verifies DuckLake is working correctly

**Expected Output:**
```
========================================== Migrating to DuckLake (LOCAL)
==========================================

✅ Found DuckDB at: /home/rob/.local/bin/duckdb
📍 Environment: LOCAL (rob-GS66-Stealth-10UG)

📦 Step 1: Creating backup...
✅ Backup created: devices.duckdb.backup_20251114_085834

📤 Step 2: Exporting existing data to Parquet...
✅ Exported 64 rows to Parquet

🦆 Step 3: Creating DuckLake catalog and structure...
✅ DuckLake catalog created
✅ DuckLake data directory created
✅ Permissions set on catalog

📥 Step 4: Importing data into DuckLake...
✅ Imported 64 rows into DuckLake

🔐 Step 5: Setting permissions...
✅ Permissions set for grafana:grafana

🧪 Step 6: Testing DuckLake access...
[Statistics displayed]

✅ Migration Complete!
```

---

## Important: DuckLake Limitations

### No PRIMARY KEY Support

**DuckLake does not support PRIMARY KEY or UNIQUE constraints** (as of v0.3).

Instead, we handle deduplication using application logic:

```sql
-- Create temp table with new data
CREATE TEMP TABLE new_measurements AS
SELECT DISTINCT ... FROM read_json_auto('data.json');

-- Insert only records that don't already exist
INSERT INTO measurements
SELECT n.*
FROM new_measurements n
LEFT JOIN measurements m
    ON n.device = m.device
    AND n.when_captured = m.when_captured
WHERE m.device IS NULL;
```

**This approach:**
- ✅ Prevents duplicate records
- ✅ Maintains data integrity
- ✅ Still enables concurrent access
- ⚠️ Slight performance overhead for large tables

For more details, see: [DUCKLAKE_LIMITATIONS.md](DUCKLAKE_LIMITATIONS.md)

---

## After Migration: Configuration

### Step 1: Restart Grafana

**Local:**
```bash
sudo systemctl restart grafana-server
```

**Server:**
```bash
sudo systemctl restart grafana-server
```

### Step 2: Update Grafana Datasource

1. Open Grafana:
   - **Local:** http://localhost:3000
   - **Server:** https://grafana.safecast.jp

2. Go to: **Configuration** → **Data Sources** → **motherduck-duckdb-datasource**

3. Update settings:

   **Database name:**
   ```
   ducklake:/var/lib/grafana/data/ducklake_catalog.db
   ```

   **Init SQL:**
   ```sql
   INSTALL ducklake;
   LOAD ducklake;
   ATTACH 'ducklake:/var/lib/grafana/data/ducklake_catalog.db' AS safecast
       (DATA_PATH '/var/lib/grafana/data/ducklake_data/');
   USE safecast;
   ```

4. Click **Save & Test**
5. Should see: ✅ "Successfully connected to database"

### Step 3: Test Data Collection Script

Use the new DuckLake-enabled script:

```bash
./devices-last-24-hours-ducklake.sh
```

**Expected Output:**
```
[Thu Nov  6 15:30:00 UTC 2025] Fetching device data and inserting into DuckLake...
[Thu Nov  6 15:30:05 UTC 2025] Inserting data into DuckLake (concurrent write)...
[Thu Nov  6 15:30:06 UTC 2025] Data inserted into DuckLake successfully!
============================================
Data pipeline completed successfully!
Total measurements in DuckLake: 1774
============================================
```

### Step 4: Test Concurrent Access

This is the critical test!

**Terminal 1:** Open Grafana dashboard in browser and keep it active

**Terminal 2:** Run the data collection script
```bash
./devices-last-24-hours-ducklake.sh
```

**Expected Result:** ✅ Both work simultaneously without any locking errors!

### Step 5: Update Cron Job (Server Only)

```bash
crontab -e

# Change from:
*/15 * * * * cd /home/grafana.safecast.jp/public_html && ./devices-last-24-hours.sh

# To:
*/15 * * * * cd /home/grafana.safecast.jp/public_html && ./devices-last-24-hours-ducklake.sh
```

---

## File Structure

After migration, you'll have:

```
/var/lib/grafana/data/
├── devices.duckdb                          # OLD (kept as backup)
├── devices.duckdb.backup_YYYYMMDD_HHMMSS  # Timestamped backup
├── ducklake_catalog.db                     # NEW: SQLite catalog
├── ducklake_catalog.db.wal                 # NEW: WAL file (if active)
└── ducklake_data/                          # NEW: Parquet data files
    └── main/
        └── measurements/
            └── [parquet files]
```

---

## Benefits

- ✅ **No more retry logic needed** - concurrent access just works
- ✅ **No plugin modification** - DuckLake is a standard DuckDB extension
- ✅ **Time travel queries** - query historical snapshots with `ducklake_snapshots()`
- ✅ **Better performance** - Parquet files are optimized for analytics
- ✅ **Scalability** - handles terabytes of data
- ✅ **ACID guarantees** - No data corruption risk

## Catalog Choice

**SQLite (Recommended for your setup):**
- ✅ Simple - no extra server
- ✅ Local file-based
- ✅ Sufficient for your workload (2 concurrent connections)
- ✅ Low maintenance
- ⚠️ Single-machine only

**PostgreSQL (If you want to scale):**
- ✅ True multi-server support
- ✅ Thousands of concurrent connections
- ✅ Full PRIMARY KEY support
- ⚠️ Requires PostgreSQL server setup
- ⚠️ More complex infrastructure

For your use case (Grafana + one data collection script), **SQLite is perfect!**

---

## Rollback Plan

If something goes wrong, you can easily rollback:

### Local Machine:
```bash
# Stop Grafana
sudo systemctl stop grafana-server

# Restore original database
sudo cp /var/lib/grafana/data/devices.duckdb.backup_* \
     /var/lib/grafana/data/devices.duckdb

# Revert Grafana datasource settings:
# - Database name: /var/lib/grafana/data/devices.duckdb
# - Init SQL: (clear)

# Start Grafana
sudo systemctl start grafana-server

# Use old script
./devices-last-24-hours.sh
```

### Server:
```bash
# Stop Grafana
sudo systemctl stop grafana-server

# Restore original database
cp /var/lib/grafana/data/devices.duckdb.backup_* \
   /var/lib/grafana/data/devices.duckdb

# Revert Grafana datasource settings

# Start Grafana
sudo systemctl start grafana-server

# Revert cron job to old script
```

Your original data is safe - migration scripts create backups before making any changes!

---

## Troubleshooting

### "DuckDB binary not found"
- **Local:** Install DuckDB to `~/.local/bin/duckdb`
- **Server:** Install DuckDB to `/root/.local/bin/duckdb`
- See: https://duckdb.org/docs/installation/

### "Permission denied" on catalog or data directory
```bash
# Local
sudo chown -R $USER:grafana /var/lib/grafana/data/ducklake_*
sudo chmod 664 /var/lib/grafana/data/ducklake_catalog.db
sudo chmod 775 /var/lib/grafana/data/ducklake_data/

# Server
chown -R grafana:grafana /var/lib/grafana/data/ducklake_*
chmod 664 /var/lib/grafana/data/ducklake_catalog.db
chmod 775 /var/lib/grafana/data/ducklake_data/
```

### "Failed to create directory" during import
This means permissions weren't set early enough. Re-run the migration script - it now sets permissions before importing data.

### Grafana shows no data after migration
1. Verify Init SQL is correct (check for typos)
2. Verify database path uses `ducklake:` prefix
3. Check Grafana logs: `sudo journalctl -u grafana-server -f`
4. Test query manually:
   ```bash
   duckdb <<EOF
   INSTALL ducklake; LOAD ducklake;
   ATTACH 'ducklake:/var/lib/grafana/data/ducklake_catalog.db' AS safecast
       (DATA_PATH '/var/lib/grafana/data/ducklake_data/');
   USE safecast;
   SELECT COUNT(*) FROM measurements;
   EOF
   ```

### Still getting locking errors
1. Verify you're using the **new** script: `devices-last-24-hours-ducklake.sh`
2. Verify Grafana is using DuckLake path (with `ducklake:` prefix)
3. Check if old cron job is still running the old script

---

## Additional Documentation

- **[IMPLEMENTATION_GUIDE.md](IMPLEMENTATION_GUIDE.md)** - Step-by-step implementation guide with checklist
- **[MIGRATION_SCRIPTS_GUIDE.md](MIGRATION_SCRIPTS_GUIDE.md)** - Detailed guide to migration scripts
- **[DUCKLAKE_LIMITATIONS.md](DUCKLAKE_LIMITATIONS.md)** - DuckLake limitations and workarounds
- **[devices-last-24-hours-ducklake.sh](devices-last-24-hours-ducklake.sh)** - New data collection script

---

## Summary: What You Get

**Before (Single File DuckDB):**
- ❌ Locking errors when Grafana and script run together
- ❌ Need retry logic (10 attempts, 3s delays)
- ❌ Not truly concurrent

**After (DuckLake):**
- ✅ True concurrent read/write access
- ✅ No locking errors
- ✅ No retry logic needed
- ✅ Grafana and script work simultaneously
- ✅ Time travel queries
- ✅ Better performance
- ✅ Scalable architecture

**Ready to migrate? Just run:**
```bash
./migrate-to-ducklake.sh
```
