#!/bin/bash

# Migrate data from DuckDB to PostgreSQL
# Exports data from DuckDB to CSV, then imports to PostgreSQL

set -e

echo "=========================================="
echo "DuckDB to PostgreSQL Data Migration"
echo "=========================================="

# Load PostgreSQL configuration
CONFIG_FILE="$(dirname "$0")/postgres-config.sh"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file not found: $CONFIG_FILE"
    echo "Please run 01-setup-database.sh first"
    exit 1
fi

source "$CONFIG_FILE"

# Find DuckDB binary
if command -v duckdb &> /dev/null; then
    DUCKDB_BIN=$(command -v duckdb)
elif [ -x "$HOME/.local/bin/duckdb" ]; then
    DUCKDB_BIN="$HOME/.local/bin/duckdb"
else
    echo "Error: DuckDB binary not found."
    exit 1
fi

# Find DuckDB database
DUCKDB_PATH="/var/lib/grafana/data/devices.duckdb"

# Check if it's a symlink (flip-flop setup)
if [ -L "$DUCKDB_PATH" ]; then
    echo "Found flip-flop setup (symlink detected)"
    DUCKDB_ACTUAL=$(readlink -f "$DUCKDB_PATH")
    echo "Using: $DUCKDB_ACTUAL"
    DUCKDB_PATH="$DUCKDB_ACTUAL"
fi

if [ ! -f "$DUCKDB_PATH" ]; then
    echo "Error: DuckDB file not found at $DUCKDB_PATH"
    echo ""
    echo "Please specify the path to your DuckDB file:"
    read -p "DuckDB path: " DUCKDB_PATH
    if [ ! -f "$DUCKDB_PATH" ]; then
        echo "Error: File not found"
        exit 1
    fi
fi

# Create temp directory for CSV exports
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo ""
echo "DuckDB: $DUCKDB_PATH"
echo "PostgreSQL: $PGDATABASE at $PGHOST"
echo "Temp directory: $TEMP_DIR"
echo ""

# Count records in DuckDB
echo "Counting records in DuckDB..."
DUCKDB_COUNT=$($DUCKDB_BIN "$DUCKDB_PATH" "SELECT COUNT(*) FROM measurements" 2>/dev/null | grep -oP '^\s*\d+' | tr -d ' ' || echo "0")
if [ -z "$DUCKDB_COUNT" ]; then
    DUCKDB_COUNT="0"
fi
echo "Found $DUCKDB_COUNT records in DuckDB measurements table"

if [ "$DUCKDB_COUNT" -eq 0 ] 2>/dev/null; then
    echo "Warning: No records found in DuckDB. Continue anyway? (y/n)"
    read -p "> " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo ""
read -p "Continue with migration? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

# Export measurements from DuckDB to CSV
echo ""
echo "Step 1/4: Exporting measurements from DuckDB..."
$DUCKDB_BIN "$DUCKDB_PATH" <<EOF
COPY (
    SELECT
        bat_voltage,
        dev_temp,
        device,
        device_sn,
        device_urn,
        device_filename,
        env_temp,
        lnd_7128ec,
        lnd_7318c,
        lnd_7318u,
        loc_country,
        loc_lat,
        loc_lon,
        loc_name,
        pms_pm02_5,
        when_captured
    FROM measurements
    WHERE when_captured IS NOT NULL
    ORDER BY when_captured
) TO '$TEMP_DIR/measurements.csv' (HEADER, DELIMITER ',');
EOF

if [ ! -f "$TEMP_DIR/measurements.csv" ]; then
    echo "Error: Export failed - CSV file not created"
    exit 1
fi

EXPORTED_ROWS=$(wc -l < "$TEMP_DIR/measurements.csv")
EXPORTED_ROWS=$((EXPORTED_ROWS - 1))  # Subtract header row
echo "Exported $EXPORTED_ROWS rows to CSV"

# Import CSV to PostgreSQL
echo ""
echo "Step 2/4: Importing to PostgreSQL measurements table..."

# Use a temp table to handle duplicates
psql <<EOF
-- Create temp table without constraints
CREATE TEMP TABLE temp_measurements (
    bat_voltage VARCHAR(50),
    dev_temp BIGINT,
    device BIGINT,
    device_sn VARCHAR(100),
    device_urn VARCHAR(100),
    device_filename VARCHAR(200),
    env_temp BIGINT,
    lnd_7128ec VARCHAR(50),
    lnd_7318c VARCHAR(50),
    lnd_7318u BIGINT,
    loc_country VARCHAR(100),
    loc_lat DOUBLE PRECISION,
    loc_lon DOUBLE PRECISION,
    loc_name VARCHAR(200),
    pms_pm02_5 VARCHAR(50),
    when_captured TIMESTAMP
);

-- Import all data into temp table
\copy temp_measurements FROM '$TEMP_DIR/measurements.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',')

-- Insert into main table, skipping duplicates
INSERT INTO measurements
SELECT DISTINCT ON (device_urn, when_captured) *
FROM temp_measurements
ON CONFLICT (device_urn, when_captured) DO NOTHING;

-- Show import stats
SELECT
    COUNT(*) as total_rows,
    MIN(when_captured) as oldest_record,
    MAX(when_captured) as newest_record,
    COUNT(DISTINCT device_urn) as unique_devices
FROM measurements;
EOF

# Refresh summary tables
echo ""
echo "Step 3/4: Refreshing summary tables..."
psql <<EOF
-- This may take a minute for large datasets
SELECT refresh_all_summaries();

-- Show summary stats
SELECT 'Hourly Summary' as table_name, COUNT(*) as rows FROM hourly_summary
UNION ALL
SELECT 'Recent Data', COUNT(*) FROM recent_data
UNION ALL
SELECT 'Daily Summary', COUNT(*) FROM daily_summary;
EOF

# Run ANALYZE to update statistics for query planner
echo ""
echo "Step 4/4: Analyzing tables (updating statistics)..."
psql <<EOF
ANALYZE measurements;
ANALYZE hourly_summary;
ANALYZE recent_data;
ANALYZE daily_summary;

SELECT 'Table statistics updated' as status;
EOF

# Show final stats
echo ""
echo "=========================================="
echo "✅ Migration Complete!"
echo "=========================================="

psql <<EOF
SELECT
    'Measurements' as table_name,
    COUNT(*) as rows,
    pg_size_pretty(pg_total_relation_size('measurements')) as size,
    MIN(when_captured) as oldest,
    MAX(when_captured) as newest
FROM measurements
\gx
EOF

echo ""
echo "Summary tables:"
psql -c "
SELECT
    table_name,
    (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I', table_name), false, true, '')))[1]::text::int AS row_count,
    pg_size_pretty(pg_total_relation_size(table_name::regclass)) as size
FROM (VALUES ('hourly_summary'), ('recent_data'), ('daily_summary')) AS t(table_name);
"

echo ""
echo "Next steps:"
echo "  1. Test queries: psql -c 'SELECT COUNT(*) FROM measurements'"
echo "  2. Update data collection: Use 04-devices-postgres.sh"
echo "  3. Configure Grafana: See 05-grafana-setup.md"
echo ""
echo "Optional: Run 06-setup-timescaledb.sh for enhanced time-series features"
echo "=========================================="
