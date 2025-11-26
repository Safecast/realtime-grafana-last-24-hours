#!/bin/bash

# -----------------------------------------------------------------------------
# Script: devices-last-24-hours-ducklake.sh
# Description: Fetches device data from Safecast TTServer API and stores it
#              in DuckLake format for concurrent read/write access.
#              - Multiple DuckDB instances can read/write simultaneously
#              - Uses SQLite catalog for transaction coordination
#              - Data stored as Parquet files (not single locked database)
#              - No JSON files created - data stored ONLY in DuckLake
# -----------------------------------------------------------------------------

# Redirect all output and errors to script.log with timestamps
exec > >(while IFS= read -r line; do echo "[$(date)] $line"; done | tee -i script.log)
exec 2>&1

# Function to find DuckDB binary
find_duckdb_binary() {
  DUCKDB_BIN=

  # First, check if duckdb is in PATH
  if command -v duckdb &> /dev/null; then
    DUCKDB_BIN=$(command -v duckdb)
    echo "Found DuckDB binary at: $DUCKDB_BIN"
    return 0
  fi

  # If not in PATH, check common installation locations
  for path in "$HOME/.local/bin/duckdb" "/usr/local/bin/duckdb" "/root/.local/bin/duckdb" "./duckdb"; do
    if [ -x "$path" ]; then
      DUCKDB_BIN="$path"
      echo "Found DuckDB binary at: $DUCKDB_BIN"
      return 0
    fi
  done

  # Not found anywhere
  echo "Error: DuckDB binary not found. Please install DuckDB and ensure it's in PATH or in one of the checked locations."
  exit 1
}

# Function to fetch device data and insert into DuckLake
fetch_and_insert_ducklake() {
  echo "Fetching device data and inserting into DuckLake..."

  # Find DuckDB binary
  find_duckdb_binary

  # DuckLake configuration
  DUCKLAKE_CATALOG="/var/lib/grafana/data/ducklake_catalog.db"
  DUCKLAKE_DATA="/var/lib/grafana/data/ducklake_data/"

  # Get the current local timestamp
  local local_time=$(date +"%Y-%m-%d %H:%M:%S")

  # Get DuckDB version
  DUCKDB_VERSION=$($DUCKDB_BIN -version 2>&1 | grep -oP 'v\K[0-9]+\.[0-9]+\.[0-9]+' || echo "1.4.1")
  echo "Using DuckDB version: $DUCKDB_VERSION"

  # Fetch data from API and process with jq
  TEMP_DATA="/dev/shm/duckdb_temp_$$.json"

  echo "Fetching and processing data..."
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
    }' > "$TEMP_DATA"

  if [ $? -ne 0 ] || [ ! -s "$TEMP_DATA" ]; then
    echo "Error: Failed to fetch or process data."
    rm -f "$TEMP_DATA"
    exit 1
  fi

  echo "Inserting data into DuckLake (concurrent write)..."

  # Insert via DuckLake - NO LOCKING ISSUES!
  $DUCKDB_BIN <<EOF
    -- Install and load DuckLake extension
    INSTALL ducklake;
    LOAD ducklake;

    -- Attach DuckLake catalog
    ATTACH 'ducklake:${DUCKLAKE_CATALOG}' AS safecast
        (DATA_PATH '${DUCKLAKE_DATA}');

    USE safecast;

    -- Enable JSON extension
    INSTALL 'json';
    LOAD 'json';

    -- Create temp table with new data
    CREATE TEMP TABLE new_measurements AS
    SELECT DISTINCT
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
    FROM read_json_auto('${TEMP_DATA}')
    WHERE TRY_CAST(when_captured AS TIMESTAMP) IS NOT NULL;

    -- Insert only records that don't already exist (deduplication)
    INSERT INTO measurements
    SELECT n.*
    FROM new_measurements n
    LEFT JOIN measurements m
        ON n.device = m.device
        AND n.when_captured = m.when_captured
    WHERE m.device IS NULL;
EOF

  if [ $? -ne 0 ]; then
    echo "Error: Failed to insert data into DuckLake."
    rm -f "$TEMP_DATA"
    exit 1
  fi

  # Clean up temp file
  rm -f "$TEMP_DATA"

  echo "Data inserted into DuckLake successfully! (No locking - concurrent access enabled)"

  # -----------------------------------------------------------------------------
  # Update Summary Tables (Optimized for Grafana)
  # -----------------------------------------------------------------------------
  echo "Updating summary tables in DuckLake..."

  $DUCKDB_BIN <<EOF
    INSTALL ducklake;
    LOAD ducklake;
    ATTACH 'ducklake:${DUCKLAKE_CATALOG}' AS safecast (DATA_PATH '${DUCKLAKE_DATA}');
    USE safecast;

    -- 1. Hourly Summary (Last 30 days)
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

    -- Refresh hourly_summary (incremental)
    DELETE FROM hourly_summary WHERE hour < NOW() - INTERVAL '30 days';

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
    WHERE when_captured >= (SELECT COALESCE(MAX(hour), NOW() - INTERVAL '30 days') FROM hourly_summary)
    GROUP BY hour, device_urn, device_sn, loc_country, loc_name, loc_lat, loc_lon;

    -- 2. Recent Data (Last 7 days raw)
    CREATE TABLE IF NOT EXISTS recent_data AS SELECT * FROM measurements WHERE 1=0;
    
    DELETE FROM recent_data;
    INSERT INTO recent_data
    SELECT * FROM measurements
    WHERE when_captured >= NOW() - INTERVAL '7 days';

    -- 3. Daily Summary (All history - for 1 year view)
    CREATE TABLE IF NOT EXISTS daily_summary (
        day TIMESTAMP,
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
    WHERE when_captured >= (SELECT COALESCE(MAX(day), '2000-01-01'::TIMESTAMP) FROM daily_summary)
    GROUP BY day, device_urn, device_sn, loc_country, loc_name, loc_lat, loc_lon;
EOF

  echo "Summary tables updated successfully!"
}

# Main Execution Flow

# Fetch device data from TTServer and insert into DuckLake
fetch_and_insert_ducklake

# Display statistics
find_duckdb_binary
DUCKLAKE_CATALOG="/var/lib/grafana/data/ducklake_catalog.db"
DUCKLAKE_DATA="/var/lib/grafana/data/ducklake_data/"

row_count=$($DUCKDB_BIN <<EOF
INSTALL ducklake;
LOAD ducklake;

ATTACH 'ducklake:${DUCKLAKE_CATALOG}' AS safecast
    (DATA_PATH '${DUCKLAKE_DATA}');

USE safecast;

SELECT COUNT(*) AS row_count FROM measurements;
EOF
)

# Trim whitespace
row_count=$(echo "$row_count" | grep -oP '\d+' | head -1)

echo ""
echo "============================================"
echo "Data pipeline completed successfully!"
echo "Total measurements in DuckLake: $row_count"
echo "============================================"
echo ""
echo "DuckLake catalog: $DUCKLAKE_CATALOG"
echo "DuckLake data: $DUCKLAKE_DATA"
echo "Concurrent access enabled - no locking issues!"
echo ""

# Display recent device activity
echo "Recent device activity:"
$DUCKDB_BIN <<EOF
INSTALL ducklake;
LOAD ducklake;

ATTACH 'ducklake:${DUCKLAKE_CATALOG}' AS safecast
    (DATA_PATH '${DUCKLAKE_DATA}');

USE safecast;

SELECT
  device_urn,
  COUNT(*) as measurement_count,
  MAX(when_captured) as last_seen
FROM measurements
GROUP BY device_urn
ORDER BY last_seen DESC
LIMIT 10;
EOF

# Close redirected file descriptors and wait for background processes
exec 1>&- 2>&-
wait

# Ensure proper exit
exit 0
