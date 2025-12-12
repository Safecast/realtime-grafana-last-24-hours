#!/bin/bash

# Safecast Device Data Collection for PostgreSQL
# Replaces: devices-last-24-hours.sh and update-flipflop-simple.sh
# No flip-flop needed! PostgreSQL handles concurrent access perfectly.

set -e

echo "=========================================="
echo "Safecast Data Collection (PostgreSQL)"
echo "=========================================="

# Load PostgreSQL configuration
SCRIPT_DIR="$(dirname "$0")"
CONFIG_FILE="$SCRIPT_DIR/postgres-config.sh"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file not found: $CONFIG_FILE"
    echo "Please run 01-setup-database.sh first"
    exit 1
fi

source "$CONFIG_FILE"

# Get current timestamp for records missing when_captured
local_time=$(date +'%Y-%m-%d %H:%M:%S')

# Create temp file for JSON data
TEMP_JSON=$(mktemp)
TEMP_CSV=$(mktemp)
trap "rm -f $TEMP_JSON $TEMP_CSV" EXIT

echo "Fetching device data from TTServer API..."

# Fetch JSON data from TTServer (no API key needed for /devices endpoint)
wget -qO- "https://tt.safecast.org/devices?template={\"when_captured\":\"\",\"device_urn\":\"\",\"device_sn\":\"\",\"device\":\"\",\"loc_name\":\"\",\"loc_country\":\"\",\"loc_lat\":0.0,\"loc_lon\":0.0,\"env_temp\":0.0,\"lnd_7318c\":\"\",\"lnd_7318u\":0.0,\"lnd_7128ec\":\"\",\"pms_pm02_5\":\"\",\"bat_voltage\":\"\",\"dev_temp\":0.0}" | \
jq -c --arg local_time "$local_time" 'unique_by(.device_urn, .when_captured) | .[] |
{
    when_captured: (if (.when_captured == null or .when_captured == "")
                    then $local_time
                    else .when_captured end),
    device_urn: (.device_urn // "0"),
    device_sn: (.device_sn // "0"),
    device: (.device // "0"),
    loc_name: (.loc_name // "0"),
    loc_country: (.loc_country // "0"),
    loc_lat: (if (.loc_lat == "" or .loc_lat == null) then 0 else .loc_lat end),
    loc_lon: (if (.loc_lon == "" or .loc_lon == null) then 0 else .loc_lon end),
    env_temp: (if (.env_temp == "" or .env_temp == null) then 0 else .env_temp end),
    lnd_7318c: (.lnd_7318c // "0"),
    lnd_7318u: (if (.lnd_7318u == "" or .lnd_7318u == null) then 0 else .lnd_7318u end),
    lnd_7128ec: (.lnd_7128ec // "0"),
    pms_pm02_5: (.pms_pm02_5 // "0"),
    bat_voltage: (if (.bat_voltage == "" or .bat_voltage == null) then 0 else .bat_voltage end),
    dev_temp: (if (.dev_temp == "" or .dev_temp == null) then 0 else .dev_temp end),
    device_filename: (if .device_urn and .device_urn != "" and .device_urn != "0"
                      then (.device_urn | gsub("[:\"]"; "_") + ".json")
                      else "unknown_device.json" end)
} | select(
    (.when_captured | test("^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])")) or
    (.when_captured == $local_time)
)' > "$TEMP_JSON"

if [ ! -s "$TEMP_JSON" ]; then
    echo "Error: Failed to fetch data from TTServer"
    exit 1
fi

RECORD_COUNT=$(wc -l < "$TEMP_JSON")
echo "Fetched $RECORD_COUNT device records"

if [ "$RECORD_COUNT" -eq 0 ]; then
    echo "No new data to process"
    exit 0
fi

# Convert JSON to CSV for PostgreSQL COPY
echo "Converting JSON to CSV..."
jq -r '[
    .bat_voltage,
    .dev_temp,
    .device,
    .device_sn,
    .device_urn,
    .device_filename,
    .env_temp,
    .lnd_7128ec,
    .lnd_7318c,
    .lnd_7318u,
    .loc_country,
    .loc_lat,
    .loc_lon,
    .loc_name,
    .pms_pm02_5,
    .when_captured
] | @csv' "$TEMP_JSON" > "$TEMP_CSV"

if [ ! -s "$TEMP_CSV" ]; then
    echo "Error: CSV conversion failed"
    exit 1
fi

# Insert data into PostgreSQL
echo "Inserting data into PostgreSQL..."

# Use a transaction for atomicity
psql <<EOF
-- Start transaction
BEGIN;

-- Create temp table for new data
CREATE TEMP TABLE new_measurements (
    bat_voltage VARCHAR(50),
    dev_temp DOUBLE PRECISION,
    device BIGINT,
    device_sn VARCHAR(100),
    device_urn VARCHAR(100),
    device_filename VARCHAR(200),
    env_temp DOUBLE PRECISION,
    lnd_7128ec VARCHAR(50),
    lnd_7318c VARCHAR(50),
    lnd_7318u DOUBLE PRECISION,
    loc_country VARCHAR(100),
    loc_lat DOUBLE PRECISION,
    loc_lon DOUBLE PRECISION,
    loc_name VARCHAR(200),
    pms_pm02_5 VARCHAR(50),
    when_captured TIMESTAMP
);

-- Import CSV into temp table (use \copy for client-side import)
\copy new_measurements FROM '$TEMP_CSV' CSV

-- Insert new records (ON CONFLICT DO NOTHING prevents duplicates)
INSERT INTO measurements
SELECT * FROM new_measurements
WHERE when_captured >= NOW() - INTERVAL '30 days'
ON CONFLICT (device_urn, when_captured) DO NOTHING;

-- Get insert count
SELECT COUNT(*) as inserted_records FROM new_measurements;

-- Commit transaction
COMMIT;
EOF

INSERT_RESULT=$?

if [ $INSERT_RESULT -ne 0 ]; then
    echo "❌ Insert failed!"
    exit 1
fi

# Refresh summary tables
echo "Refreshing summary tables..."

psql <<EOF
-- Refresh all summary tables
SELECT refresh_all_summaries();

-- Show stats
SELECT
    'Measurements' as table_name,
    COUNT(*) as total_rows,
    COUNT(DISTINCT device_urn) as unique_devices,
    MAX(when_captured) as latest_reading
FROM measurements
UNION ALL
SELECT
    'Hourly Summary',
    COUNT(*),
    COUNT(DISTINCT device_urn),
    MAX(hour)
FROM hourly_summary
UNION ALL
SELECT
    'Recent Data',
    COUNT(*),
    COUNT(DISTINCT device_urn),
    MAX(when_captured)
FROM recent_data;
EOF

echo ""
echo "=========================================="
echo "✅ Data Collection Complete!"
echo "=========================================="
echo ""
echo "Processed: $RECORD_COUNT records"
echo "Time: $(date)"
echo ""
echo "Note: No Grafana restart needed! PostgreSQL handles concurrent access."
echo "=========================================="
