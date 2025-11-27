#!/bin/bash

# Export DuckLake data to standard DuckDB for Grafana

DUCKLAKE_CATALOG="/var/lib/grafana/data/ducklake_catalog.db"
DUCKLAKE_DATA="/var/lib/grafana/data/ducklake_data/"
OUTPUT_DB="/var/lib/grafana/data/devices.duckdb"

echo "Exporting DuckLake to standard DuckDB for Grafana..."

# Find DuckDB binary
if command -v duckdb &> /dev/null; then
    DUCKDB_BIN=$(command -v duckdb)
elif [ -x "$HOME/.local/bin/duckdb" ]; then
    DUCKDB_BIN="$HOME/.local/bin/duckdb"
else
    echo "Error: DuckDB binary not found."
    exit 1
fi

# Export from DuckLake to standard DuckDB
$DUCKDB_BIN <<EOF
INSTALL ducklake;
LOAD ducklake;

-- Attach DuckLake source
ATTACH 'ducklake:${DUCKLAKE_CATALOG}' AS source (DATA_PATH '${DUCKLAKE_DATA}');

-- Attach standard DuckDB destination
ATTACH '${OUTPUT_DB}' AS dest;

-- Create table in destination
CREATE OR REPLACE TABLE dest.measurements AS SELECT * FROM source.measurements;

-- Create summary tables
CREATE OR REPLACE TABLE dest.hourly_summary AS SELECT * FROM source.hourly_summary;
CREATE OR REPLACE TABLE dest.recent_data AS SELECT * FROM source.recent_data;
CREATE OR REPLACE TABLE dest.daily_summary AS SELECT * FROM source.daily_summary;

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS dest.idx_when_captured ON dest.measurements(when_captured);
CREATE INDEX IF NOT EXISTS dest.idx_device_urn ON dest.measurements(device_urn);
CREATE INDEX IF NOT EXISTS dest.idx_device_time ON dest.measurements(device_urn, when_captured);

DETACH source;
DETACH dest;
EOF

echo "✅ Export complete! Grafana can now read from: $OUTPUT_DB"
