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
  echo "Checked locations:"
  echo "  - System PATH"
  echo "  - $HOME/.local/bin/duckdb"
  echo "  - /usr/local/bin/duckdb"
  echo "  - /root/.local/bin/duckdb"
  echo "  - ./duckdb"
  exit 1
}

# Function to fetch device data and insert directly into DuckDB (no intermediate JSON files)
fetch_and_insert_direct() {
  echo "Fetching device data and inserting directly into DuckDB..."

  # Find DuckDB binary
  find_duckdb_binary

  # Database path - accessible by both rob and grafana
  DB_PATH="/var/lib/grafana/data/devices.duckdb"

  # Get the current local timestamp in the required format
  local local_time=$(date +"%Y-%m-%d %H:%M:%S")

  # Get DuckDB version for logging
  DUCKDB_VERSION=$($DUCKDB_BIN -version 2>&1 | grep -oP 'v\K[0-9]+\.[0-9]+\.[0-9]+' || echo "1.4.1")
  echo "Using DuckDB version: $DUCKDB_VERSION"

  # Fetch data from API and process with jq
  # Use temp file in /dev/shm (RAM disk) for minimal disk I/O
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

  echo "Inserting data into DuckDB (quick write transaction)..."
  # Quick database transaction - minimizes lock time
  # Retry logic: if database is locked, wait and retry up to 10 times
  MAX_RETRIES=10
  RETRY_DELAY=3
  ATTEMPT=1

  while [ $ATTEMPT -le $MAX_RETRIES ]; do
    if [ $ATTEMPT -gt 1 ]; then
      echo "Retry attempt $ATTEMPT of $MAX_RETRIES (waiting ${RETRY_DELAY}s for database lock to release)..."
      sleep $RETRY_DELAY
    fi

    $DUCKDB_BIN "$DB_PATH" "
      -- Enable WAL mode for concurrent access (allows Grafana to read while we write)
      PRAGMA wal_autocheckpoint='1GB';

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
      FROM read_json_auto('$TEMP_DATA')
      WHERE TRY_CAST(when_captured AS TIMESTAMP) IS NOT NULL;

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

      -- Analyze the table for better query planning
      ANALYZE measurements;
    " 2>&1

    DB_EXIT_CODE=$?

    if [ $DB_EXIT_CODE -eq 0 ]; then
      echo "Database insert successful on attempt $ATTEMPT"
      break
    else
      echo "Database insert failed on attempt $ATTEMPT (exit code: $DB_EXIT_CODE)"
      if [ $ATTEMPT -eq $MAX_RETRIES ]; then
        echo "Error: Failed to insert data into DuckDB after $MAX_RETRIES attempts."
        rm -f "$TEMP_DATA"
        exit 1
      fi
      ATTEMPT=$((ATTEMPT + 1))
    fi
  done

  # Clean up temp file
  rm -f "$TEMP_DATA"

  echo "Data fetched and inserted into DuckDB successfully (temp file in RAM, then quick insert)."
}

# Main Execution Flow

# Step 1: Fetch device data from TTServer and insert directly into DuckDB
# NO JSON files are created! Data is stored ONLY in DuckDB.
fetch_and_insert_direct

# Step 1.5: Update summary tables for fast Grafana queries
echo "Updating summary tables for fast Grafana queries..."
find_duckdb_binary
DB_PATH="/var/lib/grafana/data/devices.duckdb"

$DUCKDB_BIN "$DB_PATH" <<EOF
-- Refresh hourly_summary table
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
GROUP BY hour, device_urn, device_sn, loc_country, loc_name, loc_lat, loc_lon
ON CONFLICT DO NOTHING;

-- Refresh recent_data table
DELETE FROM recent_data;
INSERT INTO recent_data
SELECT * FROM measurements
WHERE when_captured >= NOW() - INTERVAL '7 days';

-- Update statistics
ANALYZE hourly_summary;
ANALYZE recent_data;
EOF

echo "Summary tables updated successfully!"

# Step 2: Display statistics
find_duckdb_binary
DB_PATH="/var/lib/grafana/data/devices.duckdb"
row_count=$($DUCKDB_BIN "$DB_PATH" <<EOF
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
echo "All data is stored in: $DB_PATH"
echo "No JSON files were created."
echo ""

# Optional: Display some statistics
echo "Recent device activity:"
$DUCKDB_BIN "$DB_PATH" "
  SELECT
    device_urn,
    COUNT(*) as measurement_count,
    MAX(when_captured) as last_seen
  FROM measurements
  GROUP BY device_urn
  ORDER BY last_seen DESC
  LIMIT 10;
"

# Close redirected file descriptors and wait for background processes
exec 1>&- 2>&-
wait

# Ensure proper exit
exit 0
