#!/bin/bash

# -----------------------------------------------------------------------------
# Script: setup-summary-tables.sh
# Description: Creates optimized summary tables for fast Grafana queries
# -----------------------------------------------------------------------------

set -e

echo "=========================================="
echo "Setting Up Optimized Summary Tables"
echo "=========================================="
echo ""

# Find DuckDB binary
if command -v duckdb &> /dev/null; then
    DUCKDB_BIN=$(command -v duckdb)
elif [ -x "$HOME/.local/bin/duckdb" ]; then
    DUCKDB_BIN="$HOME/.local/bin/duckdb"
elif [ -x "/root/.local/bin/duckdb" ]; then
    DUCKDB_BIN="/root/.local/bin/duckdb"
else
    echo "❌ Error: DuckDB binary not found."
    exit 1
fi

DB_FILE="/var/lib/grafana/data/devices.duckdb"

echo "✅ DuckDB: $DUCKDB_BIN"
echo "✅ Database: $DB_FILE"
echo ""

# Create hourly summary table
echo "📊 Creating hourly_summary table..."
$DUCKDB_BIN "$DB_FILE" <<EOF
-- Drop existing table if it exists
DROP TABLE IF EXISTS hourly_summary;

-- Create hourly summary table
CREATE TABLE hourly_summary AS
SELECT
    DATE_TRUNC('hour', when_captured) as hour,
    device_urn,
    device_sn,
    loc_country,
    loc_name,
    loc_lat,
    loc_lon,
    COUNT(*) as reading_count,
    AVG(TRY_CAST(lnd_7318u AS DOUBLE)) as avg_radiation,
    MAX(TRY_CAST(lnd_7318u AS DOUBLE)) as max_radiation,
    MIN(TRY_CAST(lnd_7318u AS DOUBLE)) as min_radiation,
    AVG(TRY_CAST(env_temp AS DOUBLE)) as avg_temp,
    MAX(TRY_CAST(env_temp AS DOUBLE)) as max_temp,
    MIN(TRY_CAST(env_temp AS DOUBLE)) as min_temp
FROM measurements
WHERE when_captured >= NOW() - INTERVAL '30 days'
GROUP BY hour, device_urn, device_sn, loc_country, loc_name, loc_lat, loc_lon;

-- Create indexes for fast queries
CREATE INDEX idx_hourly_hour ON hourly_summary(hour);
CREATE INDEX idx_hourly_device ON hourly_summary(device_urn);
CREATE INDEX idx_hourly_country ON hourly_summary(loc_country);
CREATE INDEX idx_hourly_device_hour ON hourly_summary(device_urn, hour);

-- Analyze for statistics
ANALYZE hourly_summary;
EOF

echo "✅ hourly_summary table created with indexes"

# Create recent data table (last 7 days raw data)
echo "📊 Creating recent_data table..."
$DUCKDB_BIN "$DB_FILE" <<EOF
-- Drop existing table if it exists
DROP TABLE IF EXISTS recent_data;

-- Create recent data table (last 7 days)
CREATE TABLE recent_data AS
SELECT *
FROM measurements
WHERE when_captured >= NOW() - INTERVAL '7 days';

-- Create indexes
CREATE INDEX idx_recent_when ON recent_data(when_captured);
CREATE INDEX idx_recent_device ON recent_data(device_urn);
CREATE INDEX idx_recent_country ON recent_data(loc_country);

-- Analyze for statistics
ANALYZE recent_data;
EOF

echo "✅ recent_data table created with indexes"

# Show statistics
echo ""
echo "📊 Table Statistics:"
$DUCKDB_BIN "$DB_FILE" <<EOF
SELECT
    'measurements' as table_name,
    COUNT(*) as row_count,
    MIN(when_captured) as earliest,
    MAX(when_captured) as latest
FROM measurements
UNION ALL
SELECT
    'hourly_summary' as table_name,
    COUNT(*) as row_count,
    MIN(hour) as earliest,
    MAX(hour) as latest
FROM hourly_summary
UNION ALL
SELECT
    'recent_data' as table_name,
    COUNT(*) as row_count,
    MIN(when_captured) as earliest,
    MAX(when_captured) as latest
FROM recent_data;
EOF

echo ""
echo "=========================================="
echo "✅ Summary Tables Created Successfully!"
echo "=========================================="
echo ""
echo "Tables created:"
echo "  1. hourly_summary   - Hourly aggregations (last 30 days)"
echo "  2. recent_data      - Raw data (last 7 days)"
echo ""
echo "These tables will be automatically maintained by the data collection script."
echo ""
echo "Next steps:"
echo "  1. Test query speed: SELECT * FROM hourly_summary WHERE hour >= NOW() - INTERVAL '24 hours'"
echo "  2. Update Grafana queries to use these tables"
echo "  3. Run data collection script to keep tables updated"
echo ""
