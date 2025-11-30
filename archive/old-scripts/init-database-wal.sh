#!/bin/bash

# -----------------------------------------------------------------------------
# Script: init-database-wal.sh
# Description: Initialize DuckDB database with WAL mode for concurrent access
#              Run this once to enable Grafana and data collection to work
#              simultaneously without locking issues.
# -----------------------------------------------------------------------------

set -e

echo "=========================================="
echo "DuckDB WAL Mode Initialization"
echo "=========================================="
echo ""

DB_PATH="/var/lib/grafana/data/devices.duckdb"

# Find DuckDB binary
if command -v duckdb &> /dev/null; then
    DUCKDB_BIN=$(command -v duckdb)
elif [ -x "$HOME/.local/bin/duckdb" ]; then
    DUCKDB_BIN="$HOME/.local/bin/duckdb"
elif [ -x "/usr/local/bin/duckdb" ]; then
    DUCKDB_BIN="/usr/local/bin/duckdb"
else
    echo "❌ Error: DuckDB binary not found."
    exit 1
fi

echo "✅ Found DuckDB at: $DUCKDB_BIN"
echo "✅ Database: $DB_PATH"
echo ""

# Check if database exists
if [ ! -f "$DB_PATH" ]; then
    echo "⚠️  Database file not found. It will be created with WAL mode enabled."
fi

echo "Configuring database for concurrent access..."
echo ""

# Initialize database with WAL mode
$DUCKDB_BIN "$DB_PATH" <<EOF
-- Enable WAL mode for concurrent read/write access
PRAGMA wal_autocheckpoint='1GB';

-- Verify settings
SELECT current_setting('wal_autocheckpoint') as wal_autocheckpoint;

-- Create table if it doesn't exist
CREATE TABLE IF NOT EXISTS measurements (
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

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_measurements_device_when_captured
ON measurements(device, when_captured);

CREATE INDEX IF NOT EXISTS idx_measurements_device_urn
ON measurements(device_urn);

-- Analyze table
ANALYZE measurements;
EOF

if [ $? -eq 0 ]; then
    echo ""
    echo "=========================================="
    echo "✅ Database initialized successfully!"
    echo "=========================================="
    echo ""
    echo "WAL mode is now enabled for concurrent access."
    echo "Grafana and the data collection script can now run simultaneously."
    echo ""
else
    echo ""
    echo "❌ Failed to initialize database."
    exit 1
fi
