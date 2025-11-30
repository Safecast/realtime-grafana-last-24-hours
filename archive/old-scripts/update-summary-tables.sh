#!/bin/bash

# -----------------------------------------------------------------------------
# Script: update-summary-tables.sh
# Description: Updates summary tables (hourly_summary, recent_data, daily_summary)
#              Run this hourly to keep summary tables fresh for fast Grafana queries
# Usage: ./update-summary-tables.sh
#        Or in cron: 0 * * * * cd /path/to/dir && ./update-summary-tables.sh >> summary.log 2>&1
# -----------------------------------------------------------------------------

set -e

echo "=========================================="
echo "Updating Summary Tables"
echo "=========================================="
date
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

echo "📊 DuckDB: $DUCKDB_BIN"
echo "📊 Database: $DB_FILE"
echo ""

# Check if summary tables exist
echo "Checking if summary tables exist..."
TABLES_EXIST=$($DUCKDB_BIN "$DB_FILE" "SELECT COUNT(*) FROM information_schema.tables WHERE table_name IN ('hourly_summary', 'recent_data', 'daily_summary');" 2>&1 | tail -1)

if [ "$TABLES_EXIST" != "3" ]; then
    echo "⚠️  Warning: Summary tables don't exist. Running setup-summary-tables.sh first..."
    ./setup-summary-tables.sh
    exit 0
fi

echo "✅ All summary tables exist"
echo ""

# Update summary tables
echo "🔄 Refreshing hourly_summary (last 30 days)..."
$DUCKDB_BIN "$DB_FILE" <<EOF
DELETE FROM hourly_summary;
INSERT INTO hourly_summary
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
WHERE when_captured >= NOW() - INTERVAL 30 DAY
GROUP BY hour, device_urn, device_sn, loc_country, loc_name, loc_lat, loc_lon;
ANALYZE hourly_summary;
EOF
echo "✅ hourly_summary updated"

echo "🔄 Refreshing recent_data (last 7 days)..."
$DUCKDB_BIN "$DB_FILE" <<EOF
DELETE FROM recent_data;
INSERT INTO recent_data
SELECT * FROM measurements
WHERE when_captured >= NOW() - INTERVAL 7 DAY;
ANALYZE recent_data;
EOF
echo "✅ recent_data updated"

echo "🔄 Refreshing daily_summary (all history)..."
$DUCKDB_BIN "$DB_FILE" <<EOF
DELETE FROM daily_summary;
INSERT INTO daily_summary
SELECT
    DATE_TRUNC('day', when_captured) as day,
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
GROUP BY day, device_urn, device_sn, loc_country, loc_name, loc_lat, loc_lon;
ANALYZE daily_summary;
EOF
echo "✅ daily_summary updated"

# Show statistics
echo ""
echo "📊 Summary Table Statistics:"
$DUCKDB_BIN "$DB_FILE" <<EOF
SELECT
    'hourly_summary' as table_name,
    COUNT(*) as row_count,
    MIN(hour) as earliest,
    MAX(hour) as latest
FROM hourly_summary
UNION ALL
SELECT
    'recent_data',
    COUNT(*),
    MIN(when_captured),
    MAX(when_captured)
FROM recent_data
UNION ALL
SELECT
    'daily_summary',
    COUNT(*),
    MIN(day),
    MAX(day)
FROM daily_summary;
EOF

echo ""
echo "=========================================="
echo "✅ Summary Tables Updated Successfully!"
echo "=========================================="
date
echo ""
