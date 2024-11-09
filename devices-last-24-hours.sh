#!/bin/bash

# Redirect all output and errors to script.log with timestamps
exec > >(while IFS= read -r line; do echo "[$(date)] $line"; done | tee -i script.log)
exec 2>&1

# Input and output files
all_devices="all_devices.json"
output_files=("last-24-hours.json" "last-24-hours-air.json" "last-24-hours-radiation-7318u.json" "last-24-hours-radiation-7318c.json" "last-24-hours-radiation-712ec.json")
device_keys=("" "pms_pm02_5" "lnd_7318u" "lnd_7318c" "lnd_7128ec")

# Function to fetch device data
fetch_data() {
  echo "Fetching device data..."
  wget "https://tt.safecast.org/devices?template={\"when_captured\":\"\",\"device_urn\":\"\",\"device_sn\":\"\",\"device\":\"\",\"loc_name\":\"\",\"loc_country\":\"\",\"loc_lat\":0.0,\"loc_lon\":0.0,\"env_temp\":0.0,\"lnd_7318c\":\"\",\"lnd_7318u\":\"\",\"lnd_7128ec\":\"\",\"pms_pm02_5\":\"\",\"bat_voltage\":\"\",\"dev_temp\":0.0}" \
      --output-document="$all_devices"

  if [ $? -ne 0 ]; then
    echo "Error: Failed to fetch device data."
    exit 1
  fi

  echo "'$all_devices' downloaded successfully."
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
  ./duckdb devices.duckdb < Duckdb.sql
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
      .when_captured != null 
      and (.when_captured | test("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$")) 
      and (now - (try (.when_captured | fromdateiso8601) catch 9999999999) < 86400) 
      and .device_sn != "RR24023"
      and .device_urn != "geigiecast:61099"'

  # Add additional key filter if provided
  if [ -n "$key" ]; then
    jq_filter="$jq_filter and .$key != \"\" and .$key != null"
  fi

  # Close the select condition and apply transformation to add device_filename
  jq_filter="$jq_filter )] | map(.device_filename = (.device_urn | gsub(\":\"; \"_\") + \".json\"))"

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
  python3 import_duckdb.py
  if [ $? -ne 0 ]; then
    echo "Error: Python script execution failed."
    exit 1
  fi
  echo "Device URN JSON files exported successfully."
}

# Main Execution Flow

# Step 1: Fetch device data
fetch_data

# Step 2: Ensure device_filename column exists
ensure_device_filename_column

# Step 3: Run DuckDB SQL script to create table if not exists and insert data
run_sql_script

# Step 4: Filter and transform devices
for i in "${!output_files[@]}"; do
  filter_devices "${device_keys[i]}" "${output_files[i]}"
done

# Confirmation messages for filtered and transformed outputs
echo "Filtered and transformed outputs written to:"
for output_file in "${output_files[@]}"; do
  echo "$output_file"
done

# Step 5: Confirmation messages with measurements
row_count=$(./duckdb devices.duckdb <<EOF
.mode csv
.headers off
SELECT COUNT(*) AS row_count FROM measurements;
EOF
)

# Trim whitespace and extract the count
row_count=$(echo "$row_count" | tr -d '[:space:]')

echo "Total measurements in DuckDB: $row_count"

# Step 6: Run the Python script to export device_urn JSON files
run_python_script
