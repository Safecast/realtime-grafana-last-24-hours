#!/bin/bash
# server-fix-measurements-table.sh
#
# Safely recreate DuckDB 'measurements' table with PRIMARY KEY constraint.
# - Backs up all existing data
# - Drops old table
# - Recreates schema with PRIMARY KEY
# - Restores data from backup
#
# Usage: bash server-fix-measurements-table.sh
#
# Run this from your project root directory.
set -e

DB_FILE="devices.duckdb"
BACKUP_JSON="measurements_backup.json"

# 1. Export current data if the table exists
echo "[DuckDB] Backing up data from 'measurements' table (if exists)..."
duckdb "$DB_FILE" "COPY (SELECT * FROM measurements) TO '$BACKUP_JSON' (FORMAT JSON) ON ERROR 'IGNORE';" || true

# 2. Drop the old measurements table
echo "[DuckDB] Dropping old 'measurements' table (if exists)..."
duckdb "$DB_FILE" "DROP TABLE IF EXISTS measurements;"

# 3. Recreate the measurements table with PK
echo "[DuckDB] Creating 'measurements' table with PRIMARY KEY..."
duckdb "$DB_FILE" "
CREATE TABLE measurements (
  bat_voltage VARCHAR,
  dev_temp BIGINT,
  device BIGINT,
  device_sn VARCHAR,
  device_urn VARCHAR,
  device_filename VARCHAR,
  env_temp BIGINT,
  lnd_7128ec VARCHAR,
  lnd_7318c VARCHAR,
  lnd_7318u BIGINT,
  loc_country VARCHAR,
  loc_lat DOUBLE,
  loc_lon DOUBLE,
  loc_name VARCHAR,
  pms_pm02_5 VARCHAR,
  when_captured TIMESTAMP,
  PRIMARY KEY (device, when_captured)
);
"

# 4. Reload backup data if backup exists
if [[ -s "$BACKUP_JSON" ]]; then
  echo "[DuckDB] Loading data from backup..."
  duckdb "$DB_FILE" "COPY measurements FROM '$BACKUP_JSON' (FORMAT JSON, AUTO_DETECT=TRUE) ON ERROR 'IGNORE';"
else
  echo "[DuckDB] No backup data to load. Table is empty."
fi

# 5. Optimize the table
echo "[DuckDB] Analyzing measurements table for performance..."
duckdb "$DB_FILE" "ANALYZE measurements;"

echo "[Done] 'measurements' table recreated with PRIMARY KEY. Historical data (if any) reloaded."






