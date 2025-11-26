#!/bin/bash

# -----------------------------------------------------------------------------
# Script: migrate-to-ducklake-local.sh
# Description: Migrates existing DuckDB database to DuckLake format
#              FOR LOCAL MACHINE (rob-GS66-Stealth-10UG)
# -----------------------------------------------------------------------------

set -e

echo "=========================================="
echo "Migrating to DuckLake (LOCAL)"
echo "=========================================="
echo ""

# Configuration - LOCAL PATHS
OLD_DB="/var/lib/grafana/data/devices.duckdb"
DUCKLAKE_CATALOG="/var/lib/grafana/data/ducklake_catalog.db"
DUCKLAKE_DATA="/var/lib/grafana/data/ducklake_data/"
EXPORT_FILE="/var/lib/grafana/data/measurements_export.parquet"

# Find DuckDB binary
if command -v duckdb &> /dev/null; then
    DUCKDB_BIN=$(command -v duckdb)
elif [ -x "$HOME/.local/bin/duckdb" ]; then
    DUCKDB_BIN="$HOME/.local/bin/duckdb"
else
    echo "❌ Error: DuckDB binary not found."
    exit 1
fi

echo "✅ Found DuckDB at: $DUCKDB_BIN"
echo "📍 Environment: LOCAL ($(hostname))"
echo ""

# Step 1: Backup existing database
echo "📦 Step 1: Creating backup..."
if [ -f "$OLD_DB" ]; then
    sudo cp "$OLD_DB" "${OLD_DB}.backup_$(date +%Y%m%d_%H%M%S)"
    echo "✅ Backup created: ${OLD_DB}.backup_$(date +%Y%m%d_%H%M%S)"
else
    echo "⚠️  Warning: Old database not found at $OLD_DB"
    echo "   Will create new DuckLake from scratch"
fi
echo ""

# Step 2: Export existing data
echo "📤 Step 2: Exporting existing data to Parquet..."
if [ -f "$OLD_DB" ]; then
    $DUCKDB_BIN "$OLD_DB" <<EOF
COPY measurements TO '$EXPORT_FILE' (FORMAT PARQUET);
EOF

    if [ -f "$EXPORT_FILE" ]; then
        EXPORT_COUNT=$($DUCKDB_BIN <<EOF
SELECT COUNT(*) FROM '$EXPORT_FILE';
EOF
)
        echo "✅ Exported $(echo $EXPORT_COUNT | grep -oP '\d+' | head -1) rows to Parquet"
    else
        echo "❌ Error: Export failed"
        exit 1
    fi
else
    echo "⚠️  Skipping export - no existing data"
fi
echo ""

# Step 3: Create DuckLake structure
echo "🦆 Step 3: Creating DuckLake catalog and structure..."

# Create data directory with proper ownership from the start
sudo mkdir -p "$DUCKLAKE_DATA"
sudo chown -R $USER:grafana "$DUCKLAKE_DATA"
sudo chmod 775 "$DUCKLAKE_DATA"

# Remove old catalog if exists (fresh start)
sudo rm -f "${DUCKLAKE_CATALOG}"*

# Create DuckLake catalog and table
$DUCKDB_BIN <<EOF
INSTALL ducklake;
LOAD ducklake;

-- Attach DuckLake with SQLite catalog
ATTACH 'ducklake:${DUCKLAKE_CATALOG}' AS safecast
    (DATA_PATH '${DUCKLAKE_DATA}');

USE safecast;

-- Create measurements table in DuckLake format
-- Note: DuckLake does not support PRIMARY KEY constraints
CREATE TABLE measurements (
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
    when_captured TIMESTAMP
);

-- Create performance indexes for time-series queries
-- Index 1: when_captured (most common - time-range queries like "last 24 hours")
CREATE INDEX IF NOT EXISTS idx_when_captured
ON measurements(when_captured);

-- Index 2: device_urn (device-specific queries)
CREATE INDEX IF NOT EXISTS idx_device_urn
ON measurements(device_urn);

-- Index 3: loc_country (geographic queries)
CREATE INDEX IF NOT EXISTS idx_loc_country
ON measurements(loc_country);

-- Index 4: Composite index for device + time queries (common in Grafana)
CREATE INDEX IF NOT EXISTS idx_device_time
ON measurements(device_urn, when_captured);

-- Index 5: Composite index for country + time queries
CREATE INDEX IF NOT EXISTS idx_country_time
ON measurements(loc_country, when_captured);
EOF

echo "✅ DuckLake catalog created: $DUCKLAKE_CATALOG"
echo "✅ DuckLake data directory: $DUCKLAKE_DATA"

# Set permissions on catalog file immediately
sudo chown $USER:grafana "${DUCKLAKE_CATALOG}"*
sudo chmod 664 "${DUCKLAKE_CATALOG}"*
echo "✅ Permissions set on catalog"
echo ""

# Step 4: Import existing data (if available)
if [ -f "$EXPORT_FILE" ]; then
    echo "📥 Step 4: Importing data into DuckLake..."

    $DUCKDB_BIN <<EOF
INSTALL ducklake;
LOAD ducklake;

ATTACH 'ducklake:${DUCKLAKE_CATALOG}' AS safecast
    (DATA_PATH '${DUCKLAKE_DATA}');

USE safecast;

-- Import from Parquet
INSERT INTO measurements
SELECT * FROM '$EXPORT_FILE';
EOF

    # Verify import
    IMPORT_COUNT=$($DUCKDB_BIN <<EOF
INSTALL ducklake;
LOAD ducklake;

ATTACH 'ducklake:${DUCKLAKE_CATALOG}' AS safecast
    (DATA_PATH '${DUCKLAKE_DATA}');

USE safecast;

SELECT COUNT(*) FROM measurements;
EOF
)

    echo "✅ Imported $(echo $IMPORT_COUNT | grep -oP '\d+' | head -1) rows into DuckLake"
    echo ""

    # Clean up export file
    sudo rm -f "$EXPORT_FILE"
else
    echo "⚠️  Step 4: Skipping import - no data to import"
    echo ""
fi

# Step 5: Set permissions
echo "🔐 Step 5: Setting permissions..."
sudo chown -R grafana:grafana "${DUCKLAKE_CATALOG}"*
sudo chown -R grafana:grafana "$DUCKLAKE_DATA"
sudo chmod 664 "${DUCKLAKE_CATALOG}"*
sudo chmod 775 "$DUCKLAKE_DATA"

# Add current user to grafana group if not already
if ! groups $USER | grep -q grafana; then
    echo "⚠️  Adding $USER to grafana group..."
    sudo usermod -a -G grafana $USER
    echo "⚠️  You need to log out and log back in for group changes to take effect!"
fi

echo "✅ Permissions set for grafana:grafana"
echo ""

# Step 6: Test DuckLake access
echo "🧪 Step 6: Testing DuckLake access..."

$DUCKDB_BIN <<EOF
INSTALL ducklake;
LOAD ducklake;

ATTACH 'ducklake:${DUCKLAKE_CATALOG}' AS safecast
    (DATA_PATH '${DUCKLAKE_DATA}');

USE safecast;

SELECT
    COUNT(*) as total_measurements,
    COUNT(DISTINCT device_urn) as unique_devices,
    MIN(when_captured) as earliest,
    MAX(when_captured) as latest
FROM measurements;
EOF

echo ""
echo "=========================================="
echo "✅ LOCAL Migration Complete!"
echo "=========================================="
echo ""
echo "Next Steps:"
echo ""
echo "1. Restart local Grafana:"
echo "   sudo systemctl restart grafana-server"
echo ""
echo "2. Update Grafana datasource (http://localhost:3000):"
echo "   - Database path: ducklake:${DUCKLAKE_CATALOG}"
echo "   - Init SQL:"
echo "     INSTALL ducklake; LOAD ducklake;"
echo "     ATTACH 'ducklake:${DUCKLAKE_CATALOG}' AS safecast (DATA_PATH '${DUCKLAKE_DATA}');"
echo "     USE safecast;"
echo ""
echo "3. Test the new script:"
echo "   ./devices-last-24-hours-ducklake.sh"
echo ""
echo "4. Test concurrent access:"
echo "   - Open Grafana dashboard"
echo "   - Run: ./devices-last-24-hours-ducklake.sh"
echo "   - Both should work simultaneously!"
echo ""
