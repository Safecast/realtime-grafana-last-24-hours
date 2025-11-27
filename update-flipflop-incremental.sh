#!/bin/bash

# Incremental flip-flop update: Only copy NEW data, then atomically switch
# Optimized for large databases (10GB+)

DUCKLAKE_CATALOG="/var/lib/grafana/data/ducklake_catalog.db"
DUCKLAKE_DATA="/var/lib/grafana/data/ducklake_data/"
DB_A="/var/lib/grafana/data/devices_a.duckdb"
DB_B="/var/lib/grafana/data/devices_b.duckdb"
ACTIVE_LINK="/var/lib/grafana/data/devices.duckdb"
STATE_FILE="/var/lib/grafana/data/.active_db"

echo "=========================================="
echo "Incremental flip-flop update starting..."
echo "=========================================="

# Find DuckDB binary
if command -v duckdb &> /dev/null; then
    DUCKDB_BIN=$(command -v duckdb)
elif [ -x "$HOME/.local/bin/duckdb" ]; then
    DUCKDB_BIN="$HOME/.local/bin/duckdb"
else
    echo "Error: DuckDB binary not found."
    exit 1
fi

# Determine which DB is currently active
if [ -f "$STATE_FILE" ]; then
    ACTIVE=$(cat "$STATE_FILE")
else
    ACTIVE="A"
fi

# Set target (inactive) DB
if [ "$ACTIVE" = "A" ]; then
    TARGET_DB="$DB_B"
    NEW_ACTIVE="B"
else
    TARGET_DB="$DB_A"
    NEW_ACTIVE="A"
fi

echo "Active DB: $ACTIVE"
echo "Updating: $TARGET_DB"

# Stop Grafana to release DuckLake catalog lock
echo "Stopping Grafana to unlock DuckLake catalog..."
sudo systemctl stop grafana-server

# Update DuckLake first
cd "$(dirname "$0")"
./devices-last-24-hours-ducklake.sh

if [ $? -ne 0 ]; then
    echo "❌ DuckLake update failed. Restarting Grafana and aborting."
    sudo systemctl start grafana-server
    exit 1
fi

# Incremental sync from DuckLake to target DB
echo "Incrementally syncing DuckLake → $TARGET_DB..."

$DUCKDB_BIN <<EOF
INSTALL ducklake;
LOAD ducklake;

-- Attach DuckLake source
ATTACH 'ducklake:${DUCKLAKE_CATALOG}' AS source (DATA_PATH '${DUCKLAKE_DATA}');

-- Attach target database
ATTACH '${TARGET_DB}' AS dest;

-- Switch to dest
USE dest;

-- Create sync metadata table (first time only)
CREATE TABLE IF NOT EXISTS sync_metadata (
    table_name VARCHAR PRIMARY KEY,
    last_sync_timestamp TIMESTAMP
);

-- Get last sync time for measurements (default to epoch if never synced)
CREATE TEMP TABLE last_sync AS
SELECT COALESCE(
    (SELECT last_sync_timestamp FROM sync_metadata WHERE table_name = 'measurements'),
    TIMESTAMP '1970-01-01 00:00:00'
) as last_ts;

-- Check if this is first sync (table doesn't exist or is empty)
CREATE TEMP TABLE is_first_sync AS
SELECT COUNT(*) = 0 as first_sync FROM information_schema.tables
WHERE table_name = 'measurements' AND table_schema = 'main';

-- If first sync, do full copy
CREATE TABLE IF NOT EXISTS measurements (
    device_id BIGINT,
    device_urn VARCHAR,
    device_sn VARCHAR,
    when_captured TIMESTAMP,
    when_uploaded TIMESTAMP,
    lnd_7318u VARCHAR,
    lnd_7318c VARCHAR,
    loc_country VARCHAR,
    loc_name VARCHAR,
    loc_lat DOUBLE,
    loc_lon DOUBLE,
    env_temp VARCHAR,
    env_humid VARCHAR,
    bat_voltage VARCHAR,
    bat_current VARCHAR
);

-- Copy new measurements only
INSERT INTO measurements
SELECT * FROM source.measurements
WHERE when_captured > (SELECT last_ts FROM last_sync);

-- Get count of new rows
CREATE TEMP TABLE new_row_count AS
SELECT COUNT(*) as new_rows FROM source.measurements
WHERE when_captured > (SELECT last_ts FROM last_sync);

-- Incrementally update summary tables
-- Only rebuild summaries for affected time periods

-- 1. Hourly summary
CREATE TABLE IF NOT EXISTS hourly_summary (
    hour TIMESTAMP,
    device_urn VARCHAR,
    device_sn VARCHAR,
    loc_country VARCHAR,
    loc_name VARCHAR,
    loc_lat DOUBLE,
    loc_lon DOUBLE,
    reading_count BIGINT,
    avg_radiation DOUBLE,
    max_radiation DOUBLE,
    min_radiation DOUBLE,
    avg_temp DOUBLE,
    max_temp DOUBLE,
    min_temp DOUBLE
);

DELETE FROM hourly_summary
WHERE hour >= (SELECT DATE_TRUNC('hour', last_ts) FROM last_sync);

INSERT INTO hourly_summary
SELECT * FROM source.hourly_summary
WHERE hour >= (SELECT DATE_TRUNC('hour', last_ts) FROM last_sync);

-- 2. Recent data (last 7 days) - full refresh since it's small
CREATE OR REPLACE TABLE recent_data AS SELECT * FROM source.recent_data;

-- 3. Daily summary
CREATE TABLE IF NOT EXISTS daily_summary (
    day DATE,
    device_urn VARCHAR,
    device_sn VARCHAR,
    loc_country VARCHAR,
    loc_name VARCHAR,
    loc_lat DOUBLE,
    loc_lon DOUBLE,
    reading_count BIGINT,
    avg_radiation DOUBLE,
    max_radiation DOUBLE,
    min_radiation DOUBLE,
    avg_temp DOUBLE,
    max_temp DOUBLE,
    min_temp DOUBLE
);

DELETE FROM daily_summary
WHERE day >= (SELECT DATE_TRUNC('day', last_ts) FROM last_sync);

INSERT INTO daily_summary
SELECT * FROM source.daily_summary
WHERE day >= (SELECT DATE_TRUNC('day', last_ts) FROM last_sync);

-- Update sync timestamp
INSERT OR REPLACE INTO sync_metadata
VALUES ('measurements', (SELECT MAX(when_captured) FROM source.measurements));

-- Create indexes (idempotent)
CREATE INDEX IF NOT EXISTS idx_when_captured ON measurements(when_captured);
CREATE INDEX IF NOT EXISTS idx_device_urn ON measurements(device_urn);
CREATE INDEX IF NOT EXISTS idx_device_time ON measurements(device_urn, when_captured);

-- Report stats
SELECT 'Synced ' || new_rows || ' new measurements' as status FROM new_row_count;
SELECT 'Last sync timestamp: ' || last_ts as info FROM last_sync;
SELECT 'New sync timestamp: ' || last_sync_timestamp as info
FROM sync_metadata WHERE table_name = 'measurements';

EOF

if [ $? -ne 0 ]; then
    echo "❌ Incremental sync failed!"
    exit 1
fi

# Atomic switch: Update symlink
echo "Switching active database to $NEW_ACTIVE..."
ln -sf "$(basename $TARGET_DB)" "$ACTIVE_LINK"
echo "$NEW_ACTIVE" > "$STATE_FILE"

# Set permissions
sudo chown grafana:grafana "$TARGET_DB"* "$ACTIVE_LINK" 2>/dev/null
sudo chmod 664 "$TARGET_DB"* 2>/dev/null

# Restart Grafana
echo "Restarting Grafana..."
sudo systemctl start grafana-server

echo ""
echo "=========================================="
echo "✅ Incremental flip-flop update complete!"
echo "Active DB: $NEW_ACTIVE ($TARGET_DB)"
echo "Grafana is back online!"
echo "=========================================="
