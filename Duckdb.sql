-- Load the JSON extension (skip INSTALL if using DuckDB >= 0.6.0)
LOAD 'json';

-- Create the measurements table if it does not already exist
CREATE TABLE IF NOT EXISTS measurements (
    bat_voltage VARCHAR,
    dev_temp BIGINT,
    device BIGINT,
    device_sn VARCHAR,
    device_urn VARCHAR,
    device_filename VARCHAR,        -- New column added
    env_temp BIGINT,
    lnd_7128ec VARCHAR,
    lnd_7318c VARCHAR,
    lnd_7318u BIGINT,
    loc_country VARCHAR,
    loc_lat DOUBLE,
    loc_lon DOUBLE,
    loc_name VARCHAR,
    pms_pm02_5 VARCHAR,
    when_captured TIMESTAMP NOT NULL,  -- Ensure this field cannot be NULL
    PRIMARY KEY (device, when_captured)
);

-- Create an index to optimize the NOT EXISTS check (optional but recommended)
CREATE INDEX IF NOT EXISTS idx_measurements_device_when_captured ON measurements (device, when_captured);

-- Insert only new measurements from last-24-hours.json, handling empty strings with try_cast
INSERT OR IGNORE INTO measurements (
    bat_voltage,
    dev_temp,
    device,
    device_sn,
    device_urn,
    device_filename,                -- Include the new field
    env_temp,
    lnd_7128ec,
    lnd_7318c,
    lnd_7318u,
    loc_country,
    loc_lat,
    loc_lon,
    loc_name,
    pms_pm02_5,
    when_captured
) 

SELECT 
    bat_voltage,
    try_cast(dev_temp AS BIGINT) AS dev_temp,
    try_cast(device AS BIGINT) AS device,
    device_sn,
    device_urn,
    COALESCE(device_filename, 'default_filename.json') AS device_filename, -- Handle NULLs for device_filename
    try_cast(env_temp AS BIGINT) AS env_temp,
    lnd_7128ec,
    lnd_7318c,
    try_cast(lnd_7318u AS BIGINT) AS lnd_7318u,
    loc_country,
    try_cast(loc_lat AS DOUBLE) AS loc_lat,
    try_cast(loc_lon AS DOUBLE) AS loc_lon,
    loc_name,
    pms_pm02_5,
    try_cast(when_captured AS TIMESTAMP) AS when_captured
FROM read_json_auto('last-24-hours.json') AS new_data
WHERE NOT EXISTS (
    SELECT 1 FROM measurements AS existing_data
    WHERE existing_data.device = new_data.device
    AND existing_data.when_captured = new_data.when_captured
)
AND try_cast(when_captured AS TIMESTAMP) IS NOT NULL ;  -- Exclude NULL values
