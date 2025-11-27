#!/bin/bash

# Flip-flop update: Write to inactive DB, then atomically switch

DUCKLAKE_CATALOG="/var/lib/grafana/data/ducklake_catalog.db"
DUCKLAKE_DATA="/var/lib/grafana/data/ducklake_data/"
DB_A="/var/lib/grafana/data/devices_a.duckdb"
DB_B="/var/lib/grafana/data/devices_b.duckdb"
ACTIVE_LINK="/var/lib/grafana/data/devices.duckdb"
STATE_FILE="/var/lib/grafana/data/.active_db"

echo "=========================================="
echo "Flip-flop update starting..."
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

# Sync from DuckLake to target DB (full copy, no locking issues since it's inactive)
echo "Syncing DuckLake → $TARGET_DB..."

$DUCKDB_BIN <<EOF
INSTALL ducklake;
LOAD ducklake;

-- Attach DuckLake source
ATTACH 'ducklake:${DUCKLAKE_CATALOG}' AS source (DATA_PATH '${DUCKLAKE_DATA}');

-- Attach target database
ATTACH '${TARGET_DB}' AS dest;

-- Full replace (target is inactive, so no locking issues)
CREATE OR REPLACE TABLE dest.measurements AS SELECT * FROM source.measurements;
CREATE OR REPLACE TABLE dest.hourly_summary AS SELECT * FROM source.hourly_summary;
CREATE OR REPLACE TABLE dest.recent_data AS SELECT * FROM source.recent_data;
CREATE OR REPLACE TABLE dest.daily_summary AS SELECT * FROM source.daily_summary;

-- Switch to dest to create indexes
USE dest;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_when_captured ON measurements(when_captured);
CREATE INDEX IF NOT EXISTS idx_device_urn ON measurements(device_urn);
CREATE INDEX IF NOT EXISTS idx_device_time ON measurements(device_urn, when_captured);
EOF

if [ $? -ne 0 ]; then
    echo "❌ Sync failed!"
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
echo "✅ Flip-flop update complete!"
echo "Active DB: $NEW_ACTIVE ($TARGET_DB)"
echo "Grafana is back online!"
echo "=========================================="
