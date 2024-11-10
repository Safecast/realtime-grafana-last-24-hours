-- Duckdb.sql

-- Drop tables if they exist (optional, for clean runs)
DROP TABLE IF EXISTS new_data;
DROP TABLE IF EXISTS measurements;

-- Create 'new_data' table with all necessary columns including 'device'
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
    lnd_7318u VARCHAR,
    lnd_7128ec VARCHAR,
    pms_pm02_5 VARCHAR,
    bat_voltage VARCHAR,
    dev_temp DOUBLE,
    device_filename VARCHAR
);

-- Create 'measurements' table without AUTO_INCREMENT
CREATE TABLE measurements (
    id INTEGER DEFAULT (rowid),
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
    lnd_7318u VARCHAR,
    lnd_7128ec VARCHAR,
    pms_pm02_5 VARCHAR,
    bat_voltage VARCHAR,
    dev_temp DOUBLE,
    device_filename VARCHAR
);

-- Insert data into 'new_data' table from JSON file
COPY new_data FROM 'last-24-hours.json' (FORMAT JSON);

-- Insert new records into 'measurements' table from 'new_data'
-- Avoid inserting duplicates based on 'device_sn' or other unique identifiers
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
SELECT
    new_data.when_captured,
    new_data.device_urn,
    new_data.device_sn,
    new_data.device,
    new_data.loc_name,
    new_data.loc_country,
    new_data.loc_lat,
    new_data.loc_lon,
    new_data.env_temp,
    new_data.lnd_7318c,
    new_data.lnd_7318u,
    new_data.lnd_7128ec,
    new_data.pms_pm02_5,
    new_data.bat_voltage,
    new_data.dev_temp,
    new_data.device_filename
FROM
    new_data
WHERE
    NOT EXISTS (
        SELECT 1 FROM measurements
        WHERE measurements.device_sn = new_data.device_sn
    );

-- Update 'measurements' table with 'device_filename' from 'new_data'
UPDATE measurements
SET device_filename = new_data.device_filename
FROM new_data
WHERE measurements.device = new_data.device;
