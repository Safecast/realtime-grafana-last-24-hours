-- Enable JSON extension
INSTALL 'json';
LOAD 'json';

-- Create or replace the table
CREATE OR REPLACE TABLE measurements AS
SELECT 
    bat_voltage,
    try_cast(dev_temp AS BIGINT) AS dev_temp,
    try_cast(device AS BIGINT) AS device,
    device_sn,
    device_urn,
    COALESCE(device_filename, 'unknown_device.json') AS device_filename,
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
FROM read_json_auto('last-24-hours.json')
WHERE try_cast(when_captured AS TIMESTAMP) IS NOT NULL;

-- Create index for better performance
CREATE INDEX IF NOT EXISTS idx_measurements_device_when_captured 
ON measurements(device, when_captured);
