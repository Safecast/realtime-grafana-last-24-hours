# Project Cleanup Summary

**Date:** 2025-11-30

## Overview

This project has been cleaned up to keep only the currently active files and their documentation. All obsolete files from previous approaches (DuckLake migration, old deployment scripts, etc.) have been archived.

---

## Current Active Files

### Core Scripts (2)
- **`update-flipflop-simple.sh`** - Main update script using flip-flop database approach
- **`devices-last-24-hours.sh`** - Data fetching script from TTServer API

### Documentation (3)
- **`README.md`** - Main project documentation
- **`SERVER_DEPLOYMENT_GUIDE.md`** - Server deployment instructions
- **`GRAFANA_QUERIES.md`** - Grafana query examples and performance tips

### Database Files (1)
- **`devices.duckdb`** - Symlink to active database (points to devices_a.duckdb or devices_b.duckdb)
- Note: The actual databases (devices_a.duckdb, devices_b.duckdb) are in `/var/lib/grafana/data/`

### Configuration Files (2)
- **`grafana-safecast-dashboard.json`** - Grafana dashboard configuration
- **`Dashboards/`** - Directory containing dashboard files

### Other
- **`.gitignore`** - Git ignore rules
- **`cron.log`** - Active cron job log (kept for monitoring)
- **`realtime-grafana-last-24-hours.code-workspace`** - VS Code workspace file

---

## Archived Files

All archived files are in the `archive/` directory:

### `archive/old-docs/` (16 files)
Documentation from previous approaches:
- BUILD_READONLY_PLUGIN.md
- CRON_SETUP.md (outdated - referenced old scripts)
- DUCKLAKE_LIMITATIONS.md
- DUCKLAKE_MIGRATION.md
- FIX_GRAFANA_PERMISSIONS.md
- GITHUB_ISSUE_COMMENT.md
- GRAFANA_DUCKDB_SETUP.md
- GRAFANA_OPTIMIZATION_GUIDE.md
- GRAFANA_SPEEDUP_GUIDE.md
- IMPLEMENTATION_COMPLETE.md
- IMPLEMENTATION_GUIDE.md
- MIGRATION_SCRIPTS_GUIDE.md
- PERFORMANCE_ANALYSIS.md
- PERFORMANCE_INDEXES.md
- PERFORMANCE_OPTIMIZATION_SUMMARY.md
- PERFORMANCE_TEST_RESULTS.md
- SERVER_DEPLOYMENT_SIMPLE.md
- Setup commands.txt
- Setup virtual host for Garfan at port 300 and server as a webpage.txt
- shell_script_data_flow.drawio.xml
- shell_script_data_flow_detailed.drawio.xml
- Duckdb.sql
- grafana-simple-dashboard.json

### `archive/old-scripts/` (16 files)
Scripts from previous approaches:
- add-performance-indexes.sh
- build-readonly-plugin.sh
- create-grafana-views.sh
- deploy-to-server.sh
- fix-cron-sudo.sh
- init-database-wal.sh
- install-grafana-duckdb-plugin.sh
- server-fix-measurements-table.sh
- setup-shared-database.sh
- setup-summary-tables.sh
- setup_duckdb_path.sh
- test-query-performance.sh
- update-database-cron.sh
- update-summary-tables.sh (now inline in update-flipflop-simple.sh)
- update-summary-with-restart.sh
- update-with-restart.sh

### `archive/old-migration/` (2 files)
Migration-related files:
- duckdb-readonly.patch
- import_duckdb.py

### `archive/ducklake-approach/` (11 files)
Complete DuckLake approach (abandoned):
- README.md
- create-grafana-view.sh
- devices-last-24-hours-ducklake.sh
- export-ducklake-to-duckdb.sh
- migrate-to-ducklake-local.sh
- migrate-to-ducklake-server.sh
- migrate-to-ducklake.sh
- sync-incremental.sh
- update-and-sync.sh
- update-flipflop-incremental.sh
- update-flipflop.sh

---

## Deleted Files

- **`2025-01-29.md`** - Empty file
- **`script.log`** - Old log file
- **`devices_local.duckdb`** - Unused test database
- **`__pycache__/`** - Python cache directory

---

## Current Architecture

The project now uses a **flip-flop database approach**:

1. Two databases: `devices_a.duckdb` and `devices_b.duckdb`
2. Symlink `devices.duckdb` points to the active database
3. Updates write to the inactive database
4. Atomic symlink switch makes new data visible
5. Grafana briefly stops during updates (~30-60 seconds)

### Update Flow
```
Every 5 minutes (cron):
  └─ update-flipflop-simple.sh
      ├─ Stop Grafana
      ├─ Fetch data from TTServer (devices-last-24-hours.sh logic)
      ├─ Write to inactive database
      ├─ Update summary tables (hourly_summary, recent_data, daily_summary)
      ├─ Flip symlink to newly updated database
      └─ Start Grafana
```

---

## How to Use

### Manual Update
```bash
./update-flipflop-simple.sh
```

### Automated Updates (Cron)
```bash
# Edit crontab
crontab -e

# Add this line for updates every 5 minutes
*/5 * * * * cd /home/rob/Documents/realtime-grafana-last-24-hours && ./update-flipflop-simple.sh >> /home/rob/Documents/realtime-grafana-last-24-hours/cron.log 2>&1
```

### Monitor Logs
```bash
tail -f /home/rob/Documents/realtime-grafana-last-24-hours/cron.log
```

---

## Benefits of Cleanup

✅ **Simplified structure** - Only 10 active files vs 54+ before  
✅ **Clear purpose** - Each file has a specific role  
✅ **Easy maintenance** - No confusion about which scripts to use  
✅ **Historical reference** - Old approaches preserved in archive/  
✅ **Better documentation** - README.md is the single source of truth  

---

## Next Steps

If you need to:
- **Deploy to server**: See `SERVER_DEPLOYMENT_GUIDE.md`
- **Create Grafana queries**: See `GRAFANA_QUERIES.md`
- **Understand the system**: See `README.md`
- **Reference old approaches**: Check `archive/` directory

---

## Archive Policy

The `archive/` directory contains:
- **Historical documentation** - For reference only
- **Abandoned approaches** - DuckLake, WAL mode, etc.
- **Old scripts** - Replaced by current flip-flop approach

**Do not use files from archive/** unless you specifically need to reference old approaches or migrate back to a previous solution.
