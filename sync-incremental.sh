#!/bin/bash

# Incremental sync from DuckLake to standard DuckDB for Grafana
# Only syncs new/changed data for minimal downtime

DUCKLAKE_CATALOG="/var/lib/grafana/data/ducklake_catalog.db"
DUCKLAKE_DATA="/var/lib/grafana/data/ducklake_data/"
GRAFANA_DB="/var/lib/grafana/data/devices.duckdb"
SYNC_STATE="/var/lib/grafana/data/.last_sync_timestamp"

echo "Starting incremental DuckLake → DuckDB sync..."

# Find DuckDB binary
if command -v duckdb &> /dev/null; then
    DUCKDB_BIN=$(command -v duckdb)
elif [ -x "$HOME/.local/bin/duckdb" ]; then
    DUCKDB_BIN="$HOME/.local/bin/duckdb"
else
    echo "Error: DuckDB binary not found."
    exit 1
fi

# Get last sync timestamp (or use a very old date for first run)
if [ -f "$SYNC_STATE" ]; then
    LAST_SYNC=$(cat "$SYNC_STATE")
else
    LAST_SYNC="2000-01-01 00:00:00"
fi

echo "Last sync: $LAST_SYNC"

# Perform incremental sync
$DUCKDB_BIN <<EOF
INSTALL ducklake;
LOAD ducklake;

-- Attach DuckLake source
ATTACH 'ducklake:${DUCKLAKE_CATALOG}' AS source (DATA_PATH '${DUCKLAKE_DATA}');

-- Attach Grafana database
ATTACH '${GRAFANA_DB}' AS dest;

-- Create tables if they don't exist (first run)
CREATE TABLE IF NOT EXISTS dest.measurements AS SELECT * FROM source.measurements WHERE 1=0;
CREATE TABLE IF NOT EXISTS dest.hourly_summary AS SELECT * FROM source.hourly_summary WHERE 1=0;
CREATE TABLE IF NOT EXISTS dest.recent_data AS SELECT * FROM source.recent_data WHERE 1=0;
CREATE TABLE IF NOT EXISTS dest.daily_summary AS SELECT * FROM source.daily_summary WHERE 1=0;

-- Incremental sync: only copy new measurements
INSERT OR REPLACE INTO dest.measurements
SELECT * FROM source.measurements
WHERE when_captured > '${LAST_SYNC}'::TIMESTAMP;

-- Full replace for summary tables (they're small and pre-aggregated)
DELETE FROM dest.hourly_summary;
INSERT INTO dest.hourly_summary SELECT * FROM source.hourly_summary;

DELETE FROM dest.recent_data;
INSERT INTO dest.recent_data SELECT * FROM source.recent_data;

DELETE FROM dest.daily_summary;
INSERT INTO dest.daily_summary SELECT * FROM source.daily_summary;

-- Switch to dest database to create indexes
USE dest;

-- Create indexes if they don't exist
CREATE INDEX IF NOT EXISTS idx_when_captured ON measurements(when_captured);
CREATE INDEX IF NOT EXISTS idx_device_urn ON measurements(device_urn);
CREATE INDEX IF NOT EXISTS idx_device_time ON measurements(device_urn, when_captured);
EOF

if [ $? -eq 0 ]; then
    # Update sync timestamp
    date '+%Y-%m-%d %H:%M:%S' > "$SYNC_STATE"
    echo "✅ Incremental sync complete!"
else
    echo "❌ Sync failed!"
    exit 1
fi
