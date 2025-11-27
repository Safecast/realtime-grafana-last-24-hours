#!/bin/bash

# Create a standard DuckDB file that acts as a "view" into DuckLake
# Grafana will connect to this file, which internally queries DuckLake

DUCKLAKE_CATALOG="/var/lib/grafana/data/ducklake_catalog.db"
DUCKLAKE_DATA="/var/lib/grafana/data/ducklake_data/"
GRAFANA_DB="/var/lib/grafana/data/grafana_view.duckdb"

echo "Creating Grafana view database..."

duckdb "$GRAFANA_DB" <<EOF
INSTALL ducklake;
LOAD ducklake;

-- Attach DuckLake
ATTACH 'ducklake:${DUCKLAKE_CATALOG}' AS ducklake_source (DATA_PATH '${DUCKLAKE_DATA}');

-- Create views that Grafana can query
CREATE OR REPLACE VIEW measurements AS SELECT * FROM ducklake_source.measurements;
CREATE OR REPLACE VIEW hourly_summary AS SELECT * FROM ducklake_source.hourly_summary;
CREATE OR REPLACE VIEW recent_data AS SELECT * FROM ducklake_source.recent_data;
CREATE OR REPLACE VIEW daily_summary AS SELECT * FROM ducklake_source.daily_summary;

-- Keep the DuckLake attachment persistent
CREATE OR REPLACE MACRO reconnect_ducklake() AS (
    ATTACH IF NOT EXISTS 'ducklake:${DUCKLAKE_CATALOG}' AS ducklake_source (DATA_PATH '${DUCKLAKE_DATA}')
);
EOF

echo "✅ Grafana view database created at: $GRAFANA_DB"
echo "Configure Grafana to use this path instead."
