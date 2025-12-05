#!/bin/bash

# Simple flip-flop: Write directly to inactive DB, no DuckLake needed
# Zero Grafana downtime - no restart required!

DB_A="/var/lib/grafana/data/devices_a.duckdb"
DB_B="/var/lib/grafana/data/devices_b.duckdb"
ACTIVE_LINK="/var/lib/grafana/data/devices.duckdb"
STATE_FILE="/var/lib/grafana/data/.active_db"

echo "=========================================="
echo "Simple flip-flop update starting..."
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

echo "Active DB: $ACTIVE (Grafana reads from this)"
echo "Target DB: $NEW_ACTIVE (Writing new data here)"

# Stop Grafana to release database locks
echo "Stopping Grafana to unlock databases..."
sudo systemctl stop grafana-server

# Fetch data from TTServer and write directly to INACTIVE database
cd "$(dirname "$0")"

echo "Fetching data from TTServer and writing to $TARGET_DB..."

# Get current timestamp for records missing when_captured
local_time=$(date +'%Y-%m-%d %H:%M:%S')

# Fetch JSON data from TTServer (no API key needed for /devices endpoint)
TEMP_JSON=$(mktemp)

echo "Fetching device data from TTServer..."
wget -qO- "https://tt.safecast.org/devices?template={\"when_captured\":\"\",\"device_urn\":\"\",\"device_sn\":\"\",\"device\":\"\",\"loc_name\":\"\",\"loc_country\":\"\",\"loc_lat\":0.0,\"loc_lon\":0.0,\"env_temp\":0.0,\"lnd_7318c\":\"\",\"lnd_7318u\":0.0,\"lnd_7128ec\":\"\",\"pms_pm02_5\":\"\",\"bat_voltage\":\"\",\"dev_temp\":0.0}" | \
jq -c --arg local_time "$local_time" 'unique_by(.device_urn, .when_captured) | .[] | {
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
}' > "$TEMP_JSON"

if [ ! -s "$TEMP_JSON" ]; then
    echo "Error: Failed to fetch data from TTServer"
    rm -f "$TEMP_JSON"
    exit 1
fi

echo "Fetched $(wc -l < "$TEMP_JSON") device records"

# Write directly to inactive database
$DUCKDB_BIN "$TARGET_DB" <<EOF
-- Create tables if not exist (matching existing schema)
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
    when_captured TIMESTAMP
);

-- Load JSON data into temp table
CREATE TEMP TABLE new_measurements AS
SELECT
    bat_voltage,
    TRY_CAST(dev_temp AS BIGINT) AS dev_temp,
    TRY_CAST(device AS BIGINT) AS device,
    device_sn,
    device_urn,
    device_filename,
    TRY_CAST(env_temp AS BIGINT) AS env_temp,
    lnd_7128ec,
    lnd_7318c,
    TRY_CAST(lnd_7318u AS BIGINT) AS lnd_7318u,
    loc_country,
    CAST(loc_lat AS DOUBLE) as loc_lat,
    CAST(loc_lon AS DOUBLE) as loc_lon,
    loc_name,
    pms_pm02_5,
    TRY_CAST(when_captured AS TIMESTAMP) as when_captured
FROM read_json_auto('$TEMP_JSON', maximum_object_size=50000000)
WHERE TRY_CAST(when_captured AS TIMESTAMP) IS NOT NULL;

-- Delete old data (keep last 30 days)
-- DELETE FROM measurements
-- WHERE when_captured < NOW() - INTERVAL 30 DAY;

-- Insert new measurements
INSERT OR IGNORE INTO measurements
SELECT * FROM new_measurements
WHERE when_captured >= NOW() - INTERVAL 30 DAY;

-- Update summary tables

-- 1. Hourly summary (last 30 days)
CREATE TABLE IF NOT EXISTS hourly_summary (
    hour TIMESTAMP,
    device_urn VARCHAR,
    device_sn VARCHAR,
    loc_country VARCHAR,
    loc_name VARCHAR,
    loc_lat DOUBLE,
    loc_lon DOUBLE,
    reading_count BIGINT,
    avg_radiation DOUBLE,
    max_radiation DOUBLE,
    min_radiation DOUBLE,
    avg_temp DOUBLE,
    max_temp DOUBLE,
    min_temp DOUBLE
);

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
    AVG(CAST(lnd_7318u AS DOUBLE)) as avg_radiation,
    MAX(CAST(lnd_7318u AS DOUBLE)) as max_radiation,
    MIN(CAST(lnd_7318u AS DOUBLE)) as min_radiation,
    AVG(CAST(env_temp AS DOUBLE)) as avg_temp,
    MAX(CAST(env_temp AS DOUBLE)) as max_temp,
    MIN(CAST(env_temp AS DOUBLE)) as min_temp
FROM measurements
WHERE when_captured >= NOW() - INTERVAL 30 DAY
GROUP BY hour, device_urn, device_sn, loc_country, loc_name, loc_lat, loc_lon;

-- 2. Recent data (last 7 days) - same schema as measurements
CREATE TABLE IF NOT EXISTS recent_data (
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

DELETE FROM recent_data;
INSERT INTO recent_data
SELECT * FROM measurements
WHERE when_captured >= NOW() - INTERVAL 7 DAY;

-- 3. Daily summary (all data)
CREATE TABLE IF NOT EXISTS daily_summary (
    day DATE,
    device_urn VARCHAR,
    device_sn VARCHAR,
    loc_country VARCHAR,
    loc_name VARCHAR,
    loc_lat DOUBLE,
    loc_lon DOUBLE,
    reading_count BIGINT,
    avg_radiation DOUBLE,
    max_radiation DOUBLE,
    min_radiation DOUBLE,
    avg_temp DOUBLE,
    max_temp DOUBLE,
    min_temp DOUBLE
);

DELETE FROM daily_summary;
INSERT INTO daily_summary
SELECT
    CAST(when_captured AS DATE) as day,
    device_urn,
    device_sn,
    loc_country,
    loc_name,
    loc_lat,
    loc_lon,
    COUNT(*) as reading_count,
    AVG(CAST(lnd_7318u AS DOUBLE)) as avg_radiation,
    MAX(CAST(lnd_7318u AS DOUBLE)) as max_radiation,
    MIN(CAST(lnd_7318u AS DOUBLE)) as min_radiation,
    AVG(CAST(env_temp AS DOUBLE)) as avg_temp,
    MAX(CAST(env_temp AS DOUBLE)) as max_temp,
    MIN(CAST(env_temp AS DOUBLE)) as min_temp
FROM measurements
GROUP BY day, device_urn, device_sn, loc_country, loc_name, loc_lat, loc_lon;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_when_captured ON measurements(when_captured);
CREATE INDEX IF NOT EXISTS idx_device_urn ON measurements(device_urn);
CREATE INDEX IF NOT EXISTS idx_device_time ON measurements(device_urn, when_captured);

-- Report stats
SELECT COUNT(*) as total_measurements FROM measurements;
SELECT COUNT(*) as new_measurements FROM new_measurements;
EOF

# Cleanup temp file
rm -f "$TEMP_JSON"

if [ $? -ne 0 ]; then
    echo "❌ Update failed! Restarting Grafana..."
    sudo systemctl start grafana-server
    exit 1
fi

# Atomic switch: Update symlink
echo ""
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
echo "✅ Simple flip-flop update complete!"
echo "Active DB: $NEW_ACTIVE ($TARGET_DB)"
echo "Grafana is back online!"
echo "=========================================="
