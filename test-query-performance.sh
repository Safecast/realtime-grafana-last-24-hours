#!/bin/bash

# -----------------------------------------------------------------------------
# Script: test-query-performance.sh
# Description: Tests DuckDB query performance to identify bottlenecks
# Usage: ./test-query-performance.sh
# -----------------------------------------------------------------------------

set -e

# Find DuckDB binary
if command -v duckdb &> /dev/null; then
    DUCKDB_BIN=$(command -v duckdb)
elif [ -x "$HOME/.local/bin/duckdb" ]; then
    DUCKDB_BIN="$HOME/.local/bin/duckdb"
else
    echo "❌ Error: DuckDB binary not found."
    exit 1
fi

# Database location
DB_FILE="/var/lib/grafana/data/devices.duckdb"

if [ ! -f "$DB_FILE" ]; then
    echo "❌ Error: Database not found at $DB_FILE"
    exit 1
fi

echo "=========================================="
echo "DuckDB Performance Test"
echo "=========================================="
echo ""
echo "Database: $DB_FILE"
echo "DuckDB: $DUCKDB_BIN"
echo ""

# Test 1: Basic statistics
echo "Test 1: Basic table statistics"
echo "-------------------------------------------"
time $DUCKDB_BIN "$DB_FILE" <<EOF
SELECT
    COUNT(*) as total_rows,
    COUNT(DISTINCT device_urn) as unique_devices,
    MIN(when_captured) as earliest,
    MAX(when_captured) as latest
FROM measurements;
EOF
echo ""

# Test 2: Last 24 hours aggregation (typical Grafana query)
echo "Test 2: Last 24 hours aggregation (typical Grafana query)"
echo "-------------------------------------------"
time $DUCKDB_BIN "$DB_FILE" <<EOF
SELECT
    device_urn,
    COUNT(*) as reading_count,
    AVG(TRY_CAST(lnd_7318u AS DOUBLE)) as avg_radiation,
    MAX(TRY_CAST(lnd_7318u AS DOUBLE)) as max_radiation,
    MIN(when_captured) as first_reading,
    MAX(when_captured) as last_reading
FROM measurements
WHERE when_captured >= NOW() - INTERVAL '24 hours'
GROUP BY device_urn
ORDER BY reading_count DESC
LIMIT 20;
EOF
echo ""

# Test 3: Date range query
echo "Test 3: Date range query (last 7 days)"
echo "-------------------------------------------"
time $DUCKDB_BIN "$DB_FILE" <<EOF
SELECT
    DATE_TRUNC('day', when_captured) as day,
    COUNT(*) as readings_per_day,
    COUNT(DISTINCT device_urn) as active_devices
FROM measurements
WHERE when_captured >= NOW() - INTERVAL '7 days'
GROUP BY day
ORDER BY day DESC;
EOF
echo ""

# Test 4: Geographic aggregation
echo "Test 4: Geographic aggregation by country"
echo "-------------------------------------------"
time $DUCKDB_BIN "$DB_FILE" <<EOF
SELECT
    loc_country,
    COUNT(*) as reading_count,
    COUNT(DISTINCT device_urn) as devices,
    AVG(TRY_CAST(lnd_7318u AS DOUBLE)) as avg_radiation
FROM measurements
WHERE loc_country IS NOT NULL
GROUP BY loc_country
ORDER BY reading_count DESC
LIMIT 10;
EOF
echo ""

# Test 5: Full table scan
echo "Test 5: Full table scan (worst case)"
echo "-------------------------------------------"
time $DUCKDB_BIN "$DB_FILE" <<EOF
SELECT COUNT(*) as total FROM measurements;
EOF
echo ""

# Test 6: Query plan analysis
echo "Test 6: Query plan for time-range query"
echo "-------------------------------------------"
$DUCKDB_BIN "$DB_FILE" <<EOF
EXPLAIN ANALYZE
SELECT
    device_urn,
    COUNT(*) as reading_count
FROM measurements
WHERE when_captured >= NOW() - INTERVAL '24 hours'
GROUP BY device_urn;
EOF
echo ""

# Test 7: Index information
echo "Test 7: Current indexes"
echo "-------------------------------------------"
$DUCKDB_BIN "$DB_FILE" <<EOF
SELECT * FROM duckdb_indexes();
EOF
echo ""

echo "=========================================="
echo "Performance Test Complete"
echo "=========================================="
echo ""
echo "Interpretation Guide:"
echo "  <100ms    = Excellent (suitable for real-time dashboards)"
echo "  100-500ms = Good (acceptable for most dashboards)"
echo "  500ms-2s  = Moderate (may need optimization)"
echo "  >2s       = Poor (needs optimization or architecture change)"
echo ""
echo "If queries are >500ms, consider:"
echo "  1. Adding indexes on when_captured, device_urn, loc_country"
echo "  2. Partitioning data by date"
echo "  3. Using DuckLake with PostgreSQL catalog for better concurrency"
echo ""
