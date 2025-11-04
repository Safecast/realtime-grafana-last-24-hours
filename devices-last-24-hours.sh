#!/bin/bash

# -----------------------------------------------------------------------------
# Script: devices-last-24-hours.sh
# Description: Fetches device data from Safecast TTServer API and stores it
#              directly in DuckDB without creating intermediate JSON files.
#              - Pipes data directly from API → jq → DuckDB
#              - Preserves all historical data (not just last 24 hours)
#              - Handles duplicate prevention via PRIMARY KEY constraint
#              - No JSON files are created - data stored ONLY in DuckDB
# -----------------------------------------------------------------------------

# Redirect all output and errors to script.log with timestamps
exec > >(while IFS= read -r line; do echo "[$(date)] $line"; done | tee -i script.log)
exec 2>&1

# Function to find DuckDB binary
find_duckdb_binary() {
  DUCKDB_BIN=
  for path in "/root/.local/bin/duckdb" "./duckdb" "/usr/local/bin/duckdb" "/home/rob/.local/bin/duckdb"; do
    if [ -x "$path" ]; then
      DUCKDB_BIN="$path"
      break
    fi
  done

  if [ -z "$DUCKDB_BIN" ]; then
    echo "Error: DuckDB binary not found. Please install DuckDB and ensure it's in PATH or in one of the checked locations."
    exit 1
  fi

  echo "Found DuckDB binary at: $DUCKDB_BIN"
}

# Function to fetch device data and insert directly into DuckDB (no intermediate JSON files)
fetch_and_insert_direct() {
  echo "Fetching device data and inserting directly into DuckDB..."

  # Find DuckDB binary
  find_duckdb_binary

  # Get the current local timestamp in the required format
  local local_time=$(date +"%Y-%m-%d %H:%M:%S")

  # Get DuckDB version for logging
  DUCKDB_VERSION=$($DUCKDB_BIN -version 2>&1 | grep -oP 'v\K[0-9]+\.[0-9]+\.[0-9]+' || echo "1.4.1")
  echo "Using DuckDB version: $DUCKDB_VERSION"

  # Fetch data from API, process with jq, and pipe directly to DuckDB
  # No intermediate JSON files are created!
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
    }' | \
  $DUCKDB_BIN devices.duckdb "
    -- Enable JSON extension
    INSTALL 'json';
    LOAD 'json';

    -- Create the table with explicit schema (only if it doesn't exist)
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

    -- Insert new measurements from stdin (piped data), preserving all historical data
    -- INSERT OR IGNORE prevents duplicates based on PRIMARY KEY
    INSERT OR IGNORE INTO measurements
    SELECT
        bat_voltage,
        TRY_CAST(dev_temp AS BIGINT) AS dev_temp,
        TRY_CAST(device AS BIGINT) AS device,
        device_sn,
        device_urn,
        COALESCE(device_filename, 'unknown_device.json') AS device_filename,
        TRY_CAST(env_temp AS BIGINT) AS env_temp,
        lnd_7128ec,
        lnd_7318c,
        TRY_CAST(lnd_7318u AS BIGINT) AS lnd_7318u,
        loc_country,
        TRY_CAST(loc_lat AS DOUBLE) AS loc_lat,
        TRY_CAST(loc_lon AS DOUBLE) AS loc_lon,
        loc_name,
        pms_pm02_5,
        TRY_CAST(when_captured AS TIMESTAMP) AS when_captured
    FROM read_json_auto('/dev/stdin')
    WHERE TRY_CAST(when_captured AS TIMESTAMP) IS NOT NULL;

    -- Create optimized indexes
    CREATE INDEX IF NOT EXISTS idx_measurements_device_when_captured
    ON measurements(device, when_captured);

    CREATE INDEX IF NOT EXISTS idx_measurements_device_urn
    ON measurements(device_urn);

    -- Analyze the table for better query planning
    ANALYZE measurements;
  "

  if [ $? -ne 0 ]; then
    echo "Error: Failed to fetch data or insert into DuckDB."
    exit 1
  fi

  echo "Data fetched and inserted directly into DuckDB (no JSON files saved to disk)."
}

# Main Execution Flow

# Step 1: Fetch device data from TTServer and insert directly into DuckDB
# NO JSON files are created! Data is stored ONLY in DuckDB.
fetch_and_insert_direct

# Step 2: Display statistics
find_duckdb_binary
row_count=$($DUCKDB_BIN devices.duckdb <<EOF
.mode csv
.headers off
SELECT COUNT(*) AS row_count FROM measurements;
EOF
)

# Trim whitespace and extract the count
row_count=$(echo "$row_count" | tr -d '[:space:]')

echo ""
echo "============================================"
echo "Data pipeline completed successfully!"
echo "Total measurements in DuckDB: $row_count"
echo "============================================"
echo ""
echo "All data is stored in: devices.duckdb"
echo "No JSON files were created."
echo ""

# Optional: Display some statistics
echo "Recent device activity:"
$DUCKDB_BIN devices.duckdb "
  SELECT
    device_urn,
    COUNT(*) as measurement_count,
    MAX(when_captured) as last_seen
  FROM measurements
  GROUP BY device_urn
  ORDER BY last_seen DESC
  LIMIT 10;
"
