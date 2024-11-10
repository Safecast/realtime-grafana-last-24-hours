-- Duckdb.sql

-- Create 'new_data' table to temporarily hold incoming data
DROP TABLE IF EXISTS new_data;
CREATE TABLE new_data (
    when_captured VARCHAR,
    device_urn VARCHAR,
    device_sn VARCHAR,
    device VARCHAR,
    loc_name VARCHAR,
    loc_country VARCHAR,
    loc_lat DOUBLE,
    loc_lon DOUBLE,
    env_temp DOUBLE,
    lnd_7318c VARCHAR,
    lnd_7318u DOUBLE,
    lnd_7128ec VARCHAR,
    pms_pm02_5 VARCHAR,
    bat_voltage VARCHAR,
    dev_temp DOUBLE,
    device_filename VARCHAR
);

-- Create 'measurements' table if it does not exist
CREATE TABLE IF NOT EXISTS measurements (
    when_captured VARCHAR,
    device_urn VARCHAR,
    device_sn VARCHAR,
    device VARCHAR,
    loc_name VARCHAR,
    loc_country VARCHAR,
    loc_lat DOUBLE,
    loc_lon DOUBLE,
    env_temp DOUBLE,
    lnd_7318c VARCHAR,
    lnd_7318u DOUBLE,
    lnd_7128ec VARCHAR,
    pms_pm02_5 VARCHAR,
    bat_voltage VARCHAR,
    dev_temp DOUBLE,
    device_filename VARCHAR
);

-- Load new data into 'new_data' table from JSON file
COPY new_data FROM 'last-24-hours.json' (FORMAT JSON);

-- Insert only unique new records into 'measurements' table
INSERT INTO measurements (
    when_captured,
    device_urn,
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
)
SELECT DISTINCT
    when_captured,
    device_urn,
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
FROM new_data
WHERE NOT EXISTS (
    SELECT 1 FROM measurements
    WHERE measurements.device_urn = new_data.device_urn
      AND measurements.when_captured = new_data.when_captured
);
