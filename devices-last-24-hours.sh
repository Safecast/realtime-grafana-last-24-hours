#!/bin/bash

# -----------------------------------------------------------------------------
# Script: devices-last-24-hours.sh
# Description: Fetches device data from Safecast API for the last 24 hours,
#              replaces empty fields with appropriate defaults,
#              ensures database columns, filters and transforms data,
#              and exports device URN JSON files.
# -----------------------------------------------------------------------------

# Redirect all output and errors to script.log with timestamps
exec > >(while IFS= read -r line; do echo "[$(date)] $line"; done | tee -i script.log)
exec 2>&1

# Input and output files
all_devices="all_devices.json"
processed_devices="processed_devices.json"  # Temporary file for processed data
output_files=("last-24-hours.json" "last-24-hours-air.json" "last-24-hours-radiation-7318u.json" "last-24-hours-radiation-7318c.json" "last-24-hours-radiation-712ec.json")
device_keys=("" "pms_pm02_5" "lnd_7318u" "lnd_7318c" "lnd_7128ec")

# Define arrays of string and numeric fields
string_fields=("when_captured" "device_urn" "device_sn" "device" "loc_name" "loc_country" "lnd_7318c" "lnd_7318u" "lnd_7128ec" "pms_pm02_5" "bat_voltage")
numeric_fields=("loc_lat" "loc_lon" "env_temp" "dev_temp")

# Function to fetch device data and process it
fetch_data() {
  echo "Fetching device data..."

  # Get the current local timestamp in the required format
  local local_time=$(date +"%Y-%m-%d %H:%M:%S")

  # Fetch data from the API and process it with jq
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
    }' > last-24-hours.json

  if [ $? -ne 0 ]; then
    echo "Error: Failed to fetch or process device data."
    exit 1
  fi

  echo "'last-24-hours.json' downloaded, filtered, and formatted successfully."
}

# Function to check and add device_filename column if it does not exist
ensure_device_filename_column() {
  local db="devices.duckdb"

  echo "Checking if 'device_filename' column exists in 'measurements' table..."

  # Run the query and capture the count
  column_exists=$(./duckdb "$db" <<EOF
.mode csv
.headers off
SELECT COUNT(*) 
FROM information_schema.columns 
WHERE LOWER(table_name) = 'measurements' 
  AND LOWER(column_name) = 'device_filename';
EOF
)

  # Trim whitespace and extract the count
  column_exists=$(echo "$column_exists" | tr -d '[:space:]')

  echo "Column existence count: $column_exists"

  if [ "$column_exists" -eq 0 ]; then
    echo "'device_filename' column does not exist. Adding the column..."

    # SQL command to add the device_filename column
    ./duckdb "$db" <<EOF
ALTER TABLE measurements ADD COLUMN device_filename VARCHAR;
EOF

    if [ $? -ne 0 ]; then
      echo "Error: Failed to add 'device_filename' column to 'measurements' table."
      exit 1
    fi

    echo "'device_filename' column added successfully."
  else
    echo "'device_filename' column already exists in 'measurements' table."
  fi
}

# Function to run the DuckDB SQL script (creates table if not exists and inserts data)
run_sql_script() {
  echo "Running DuckDB SQL script to create table and insert data..."

  # Check if Duckdb.sql exists
  if [ ! -f "Duckdb.sql" ]; then
    echo "Error: 'Duckdb.sql' not found in the current directory."
    exit 1
  fi

  # Modify the SQL script to use INSERT OR IGNORE with parameterized values
  sed -i 's/INSERT INTO measurements/INSERT OR IGNORE INTO measurements/' Duckdb.sql

  # Ensure the 'when_captured' column allows NULLs and insert data
  ./duckdb devices.duckdb <<EOF
-- Create the table if it doesn't exist, and ensure 'when_captured' allows NULL
CREATE TABLE IF NOT EXISTS measurements (
  device_urn VARCHAR PRIMARY KEY,
  when_captured TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  device_sn VARCHAR,
  device VARCHAR,
  loc_name VARCHAR,
  loc_country VARCHAR,
  loc_lat FLOAT,
  loc_lon FLOAT,
  env_temp FLOAT,
  lnd_7318c VARCHAR,
  lnd_7318u FLOAT,
  lnd_7128ec VARCHAR,
  pms_pm02_5 VARCHAR,
  bat_voltage FLOAT,
  dev_temp FLOAT,
  device_filename VARCHAR
);

-- Insert data ignoring duplicates based on device_urn and when_captured
INSERT OR IGNORE INTO measurements (
  device_urn,
  when_captured,
  device_sn,
  device,
  loc_name,
  loc_country,
  loc_lat,
  loc_lon,
  env_temp,
  lnd_7318c,
  lnd_7318u,
  lnd_7128ec,
  pms_pm02_5,
  bat_voltage,
  dev_temp,
  device_filename
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
EOF

  if [ $? -ne 0 ]; then
    echo "Error: DuckDB SQL script execution failed."
    exit 1
  fi
  echo "DuckDB SQL script executed successfully."
}

# Function to filter devices based on provided key and transform device_urn to add device_filename
filter_devices() {
  local key="$1"
  local output_file="$2"

  echo "Filtering and transforming devices for '$output_file'..."

  # Base jq filter for selecting devices
  jq_filter='[
    .[] | select(
      .when_captured != "0" 
      and (.when_captured | test("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$")) 
      and (now - (try (.when_captured | fromdateiso8601) catch 9999999999) < 86400) 
      and .device_sn != "RR24023"
      and .device_urn != "geigiecast:61099"'

  # Add additional key filter if provided
  if [ -n "$key" ]; then
    jq_filter="$jq_filter and .$key != \"0\""
  fi

  # Close the select condition
  jq_filter="$jq_filter )"

  # Apply transformation to add device_filename, ensuring device_urn is a string
  jq_filter="$jq_filter ] | map(.device_filename = (.device_urn | tostring | gsub(\":\"; \"_\") + \".json\"))"

  # Apply the jq filter to the all_devices.json and output to the specified output file
  if ! jq "$jq_filter" "$all_devices" > "$output_file"; then
    echo "Error: jq transformation failed for $output_file."
    exit 1
  fi

  echo "'$output_file' created with 'device_filename' field."
}

# Function to run Python script
run_python_script() {
  echo "Running Python script to export device_urn JSON files..."

  # Check if the Python script exists
  if [ ! -f "import_duckdb.py" ]; then
    echo "Error: 'import_duckdb.py' not found in the current directory."
    exit 1
  fi

  python3 import_duckdb.py
  if [ $? -ne 0 ]; then
    echo "Error: Python script execution failed."
    exit 1
  fi
  echo "Device URN JSON files exported successfully."
}

# Function to validate processed JSON data
validate_data() {
  echo "Validating processed data..."

  # Check for any records missing the 'device' field
  missing_device=$(jq 'map(select(.device == null))' "$all_devices")
  if [ "$missing_device" != "[]" ]; then
    echo "Warning: Some records are missing the 'device' field."
  else
    echo "All records contain the 'device' field."
  fi

  # Check for any non-string types in string fields
  for field in "${string_fields[@]}"; do
    non_string=$(jq "map(select(.${field} | type != \"string\"))" "$all_devices")
    if [ "$non_string" != "[]" ]; then
      echo "Warning: Field '$field' has non-string values."
    fi
  done

  # Check for any non-number types in numeric fields
  for field in "${numeric_fields[@]}"; do
    non_number=$(jq "map(select(.${field} | type != \"number\"))" "$all_devices")
    if [ "$non_number" != "[]" ]; then
      echo "Warning: Field '$field' has non-numeric values."
    fi
  done

  echo "Validation completed."
}

# Main Execution Flow

# Step 1: Fetch device data and process it
fetch_data

# Step 2: Validate processed data
validate_data

# Step 3: Run DuckDB SQL script to create table if not exists and insert data
run_sql_script

# Step 4: Ensure device_filename column exists
ensure_device_filename_column

# Step 5: Filter and transform devices
for i in "${!output_files[@]}"; do
  filter_devices "${device_keys[i]}" "${output_files[i]}"
done

# Confirmation messages for filtered and transformed outputs
echo "Filtered and transformed outputs written to:"
for output_file in "${output_files[@]}"; do
  echo "$output_file"
done

# Step 6: Confirmation messages with measurements
row_count=$(./duckdb devices.duckdb <<EOF
.mode csv
.headers off
SELECT COUNT(*) AS row_count FROM measurements;
EOF
)

# Trim whitespace and extract the count
row_count=$(echo "$row_count" | tr -d '[:space:]')

echo "Total measurements in DuckDB: $row_count"

# Step 7: Run the Python script to export device_urn JSON files
run_python_script
