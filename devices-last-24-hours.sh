#!/bin/bash

# Input and output files
all_devices="all_devices.json"
output_files=("last-24-hours.json" "last-24-hours-air.json" "last-24-hours-radiation-7318u.json" "last-24-hours-radiation-7318c.json" "last-24-hours-radiation-712ec.json")
device_keys=("" "pms_pm02_5" "lnd_7318u" "lnd_7318c" "lnd_7128ec")

# Fetch device data
wget "https://tt.safecast.org/devices?template={\"when_captured\":\"\",\"device_urn\":\"\",\"device_sn\":\"\",\"device\":\"\",\"loc_name\":\"\",\"loc_country\":\"\",\"loc_lat\":0.0,\"loc_lon\":0.0,\"env_temp\":0.0,\"lnd_7318c\":\"\",\"lnd_7318u\":\"\",\"lnd_7128ec\":\"\",\"pms_pm02_5\":\"\",\"bat_voltage\":\"\",\"dev_temp\":0.0}" \
    --output-document="$all_devices"

# Function to filter devices based on provided key
filter_devices() {
  local key="$1"
  local output_file="$2"

  jq_filter='[.[] | select(.when_captured != null 
             and (.when_captured | test("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$")) 
             and (now - (try (.when_captured | fromdateiso8601) catch 9999999999) < 86400) 
             and .device_sn != "RR24023"
             and .device_urn != "geigiecast:61099"'  # Exclude device_sn RR24023 and device_urn geigiecast:61099

  # Add additional key filter if provided
  if [ -n "$key" ]; then
    jq_filter="$jq_filter and .$key != \"\" and .$key != null"
  fi

  jq_filter="$jq_filter)]"
  
  jq "$jq_filter" "$all_devices" > "$output_file"
}

# Loop through the keys and output files to process
for i in "${!output_files[@]}"; do
  filter_devices "${device_keys[i]}" "${output_files[i]}"
done

# Confirmation messages
echo "Filtered outputs written to:"
for output_file in "${output_files[@]}"; do
  echo "$output_file"
done


# run  the SQL script to update the measurements table
./duckdb devices.duckdb < Duckdb.sql

# Confirmation messages
echo "DuckDB updated"

# Confirmation messages with measurements
./duckdb devices.duckdb "SELECT COUNT(*) AS row_count FROM measurements;"

# Step 3: Run the Python script to export device_urn JSON files
python3 import_duckdb.py  

# Final confirmation
echo "Device URN JSON files exported."

