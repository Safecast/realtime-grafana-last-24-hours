#!/bin/bash

# -----------------------------------------------------------------------------
# Script: devices-last-24-hours.sh
# Description: Fetches device data from Safecast TTServer API and stores it
#              into Postgres using `psql` (no DuckDB). Behavior preserved:
#              - Pipes data from API → jq → staging CSV → Postgres
#              - Preserves all historical data (not just last 24 hours)
#              - Prevents duplicates using the existing PRIMARY KEY in Postgres
#              - No permanent intermediate JSON files are created (uses /dev/shm)
# -----------------------------------------------------------------------------

# Redirect all output and errors to script.log with timestamps
exec > >(while IFS= read -r line; do echo "[$(date)] $line"; done | tee -i script.log)
exec 2>&1

# Function to find DuckDB binary
find_psql_binary() {
  PSQL_BIN=

  if command -v psql &> /dev/null; then
    PSQL_BIN=$(command -v psql)
    echo "Found psql binary at: $PSQL_BIN"
    return 0
  fi

  for path in "$HOME/.local/bin/psql" "/usr/local/bin/psql" "/usr/bin/psql"; do
    if [ -x "$path" ]; then
      PSQL_BIN="$path"
      echo "Found psql binary at: $PSQL_BIN"
      return 0
    fi
  done

  echo "Error: psql binary not found. Please install PostgreSQL client and ensure 'psql' is in PATH."
  exit 1
}

# Function to fetch device data and insert directly into DuckDB (no intermediate JSON files)
fetch_and_insert_direct() {
  echo "Fetching device data and inserting into Postgres (via psql)..."

  # Find psql binary
  find_psql_binary

  # Use environment variables for connection: PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD
  # Optionally a full connection string can be passed in PG_CONN (psql understands it).

  # Get the current local timestamp in the required format
  local local_time=$(date +"%Y-%m-%d %H:%M:%S")

  # Use temp file in /dev/shm (RAM disk) for minimal disk I/O; CSV for fast bulk load
  TEMP_DATA="/dev/shm/psql_temp_$$.csv"

    echo "Fetching and processing data to CSV..."
    wget -qO- "https://tt.safecast.org/devices?template={\"when_captured\":\"\",\"device_urn\":\"\",\"device_sn\":\"\",\"device\":\"\",\"loc_name\":\"\",\"loc_country\":\"\",\"loc_lat\":0.0,\"loc_lon\":0.0,\"env_temp\":0.0,\"lnd_7318c\":\"\",\"lnd_7318u\":0.0,\"lnd_7128ec\":\"\",\"pms_pm02_5\":\"\",\"bat_voltage\":\"\",\"dev_temp\":0.0}" | \
    jq -r --arg local_time "$local_time" 'unique_by(.device_urn, .when_captured) | .[] | {
      when_captured: (if (.when_captured == null or .when_captured == "" or (.when_captured | test("^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T.*Z$") | not)) then $local_time else .when_captured end),
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
      device_filename: (if .device_urn and .device_urn != "" and .device_urn != "0" then (.device_urn | gsub("[:\"]"; "_") + ".json") else "unknown_device.json" end)
    } | [ .when_captured, .device_urn, .device_sn, .device, .loc_name, .loc_country, (.loc_lat|tostring), (.loc_lon|tostring), (.env_temp|tostring), .lnd_7318c, (.lnd_7318u|tostring), .lnd_7128ec, .pms_pm02_5, .bat_voltage, (.dev_temp|tostring), .device_filename ] | @csv' > "$TEMP_DATA"

  if [ $? -ne 0 ] || [ ! -s "$TEMP_DATA" ]; then
    echo "Error: Failed to fetch or process data."
    rm -f "$TEMP_DATA"
    exit 1
  fi

  echo "Loading CSV into Postgres (staging then insert with dedupe check)..."

  # Single attempt to load staging CSV and insert into measurements.
  $PSQL_BIN "${PG_CONN:-}" -v ON_ERROR_STOP=1 <<SQL
    CREATE TEMP TABLE IF NOT EXISTS measurements_staging (
      when_captured TEXT,
      device_urn TEXT,
      device_sn TEXT,
      device TEXT,
      loc_name TEXT,
      loc_country TEXT,
      loc_lat TEXT,
      loc_lon TEXT,
      env_temp TEXT,
      lnd_7318c TEXT,
      lnd_7318u TEXT,
      lnd_7128ec TEXT,
      pms_pm02_5 TEXT,
      bat_voltage TEXT,
      dev_temp TEXT,
      device_filename TEXT
    );

    \copy measurements_staging (when_captured, device_urn, device_sn, device, loc_name, loc_country, loc_lat, loc_lon, env_temp, lnd_7318c, lnd_7318u, lnd_7128ec, pms_pm02_5, bat_voltage, dev_temp, device_filename) FROM '$TEMP_DATA' WITH CSV;

    INSERT INTO measurements (when_captured, device_urn, device_sn, device, loc_name, loc_country, loc_lat, loc_lon, env_temp, lnd_7318c, lnd_7318u, lnd_7128ec, pms_pm02_5, bat_voltage, dev_temp, device_filename)
    SELECT
      NULLIF(s.when_captured,'')::timestamp,
      s.device_urn,
      s.device_sn,
      CASE WHEN s.device ~ '^\\d+$' THEN s.device::bigint ELSE NULL END,
      s.loc_name,
      s.loc_country,
      CASE WHEN s.loc_lat ~ '^-?[0-9]+(\\.[0-9]+)?$' THEN s.loc_lat::double precision ELSE NULL END,
      CASE WHEN s.loc_lon ~ '^-?[0-9]+(\\.[0-9]+)?$' THEN s.loc_lon::double precision ELSE NULL END,
      CASE WHEN s.env_temp ~ '^-?[0-9]+(\\.[0-9]+)?$' THEN s.env_temp::double precision ELSE NULL END,
      s.lnd_7318c,
      CASE WHEN s.lnd_7318u ~ '^-?[0-9]+(\\.[0-9]+)?$' THEN s.lnd_7318u::double precision ELSE NULL END,
      s.lnd_7128ec,
      s.pms_pm02_5,
      s.bat_voltage,
      CASE WHEN s.dev_temp ~ '^-?[0-9]+(\\.[0-9]+)?$' THEN s.dev_temp::double precision ELSE NULL END,
      s.device_filename
    FROM measurements_staging s
    WHERE NOT EXISTS (
      SELECT 1 FROM measurements m
      WHERE m.device_urn IS NOT DISTINCT FROM s.device_urn
        AND m.when_captured IS NOT DISTINCT FROM (NULLIF(s.when_captured,'')::timestamp)
    );
SQL

  DB_EXIT_CODE=$?
  if [ $DB_EXIT_CODE -ne 0 ]; then
    echo "Error: Failed to insert data into Postgres (exit code: $DB_EXIT_CODE)."
    rm -f "$TEMP_DATA"
    exit 1
  fi

  rm -f "$TEMP_DATA"

  echo "Data fetched and inserted into Postgres successfully (temp CSV in RAM, then staged insert)."
}

# Main Execution Flow

# Step 1: Fetch device data from TTServer and insert directly into DuckDB
# NO JSON files are created! Data is stored ONLY in DuckDB.
fetch_and_insert_direct

# Step 2: Display statistics (Postgres)
find_psql_binary
row_count=$($PSQL_BIN "${PG_CONN:-}" -Atc "SELECT COUNT(*) FROM measurements;")

echo ""
echo "============================================"
echo "Data pipeline completed successfully!"
echo "Total measurements in Postgres: ${row_count:-0}"
echo "============================================"
echo ""

# Optional: Display some statistics
echo "Recent device activity:"
$PSQL_BIN "${PG_CONN:-}" -c "SELECT
  device_urn,
  COUNT(*) as measurement_count,
  MAX(when_captured) as last_seen
FROM measurements
GROUP BY device_urn
ORDER BY last_seen DESC
LIMIT 10;"

# Close redirected file descriptors and wait for background processes
exec 1>&- 2>&-
wait

# Ensure proper exit
exit 0
