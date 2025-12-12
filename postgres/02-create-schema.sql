-- PostgreSQL Schema for Safecast Radiation Monitoring
-- Matches the DuckDB schema but optimized for PostgreSQL

-- Enable extensions (optional but useful)
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;  -- Query performance monitoring

-- Main measurements table
CREATE TABLE IF NOT EXISTS measurements (
    bat_voltage VARCHAR(50),
    dev_temp DOUBLE PRECISION,
    device BIGINT,
    device_sn VARCHAR(100),
    device_urn VARCHAR(100) NOT NULL,
    device_filename VARCHAR(200),
    env_temp DOUBLE PRECISION,
    lnd_7128ec VARCHAR(50),
    lnd_7318c VARCHAR(50),
    lnd_7318u DOUBLE PRECISION,
    loc_country VARCHAR(100),
    loc_lat DOUBLE PRECISION,
    loc_lon DOUBLE PRECISION,
    loc_name VARCHAR(200),
    pms_pm02_5 VARCHAR(50),
    when_captured TIMESTAMP NOT NULL,

    -- Primary key for deduplication
    PRIMARY KEY (device_urn, when_captured)
);

-- Create indexes for fast queries
CREATE INDEX IF NOT EXISTS idx_when_captured ON measurements(when_captured);
CREATE INDEX IF NOT EXISTS idx_device_urn ON measurements(device_urn);
CREATE INDEX IF NOT EXISTS idx_device_time ON measurements(device_urn, when_captured);
CREATE INDEX IF NOT EXISTS idx_loc_country ON measurements(loc_country);

-- Hourly summary table (last 30 days)
CREATE TABLE IF NOT EXISTS hourly_summary (
    hour TIMESTAMP NOT NULL,
    device_urn VARCHAR(100) NOT NULL,
    device_sn VARCHAR(100),
    loc_country VARCHAR(100),
    loc_name VARCHAR(200),
    loc_lat DOUBLE PRECISION,
    loc_lon DOUBLE PRECISION,
    reading_count BIGINT,
    avg_radiation DOUBLE PRECISION,
    max_radiation DOUBLE PRECISION,
    min_radiation DOUBLE PRECISION,
    avg_temp DOUBLE PRECISION,
    max_temp DOUBLE PRECISION,
    min_temp DOUBLE PRECISION,

    PRIMARY KEY (hour, device_urn)
);

CREATE INDEX IF NOT EXISTS idx_hourly_hour ON hourly_summary(hour);
CREATE INDEX IF NOT EXISTS idx_hourly_device ON hourly_summary(device_urn);

-- Recent data table (last 7 days) - same schema as measurements
CREATE TABLE IF NOT EXISTS recent_data (
    bat_voltage VARCHAR(50),
    dev_temp DOUBLE PRECISION,
    device BIGINT,
    device_sn VARCHAR(100),
    device_urn VARCHAR(100) NOT NULL,
    device_filename VARCHAR(200),
    env_temp DOUBLE PRECISION,
    lnd_7128ec VARCHAR(50),
    lnd_7318c VARCHAR(50),
    lnd_7318u DOUBLE PRECISION,
    loc_country VARCHAR(100),
    loc_lat DOUBLE PRECISION,
    loc_lon DOUBLE PRECISION,
    loc_name VARCHAR(200),
    pms_pm02_5 VARCHAR(50),
    when_captured TIMESTAMP NOT NULL,

    PRIMARY KEY (device_urn, when_captured)
);

CREATE INDEX IF NOT EXISTS idx_recent_when ON recent_data(when_captured);
CREATE INDEX IF NOT EXISTS idx_recent_device ON recent_data(device_urn);

-- Daily summary table (all data)
CREATE TABLE IF NOT EXISTS daily_summary (
    day DATE NOT NULL,
    device_urn VARCHAR(100) NOT NULL,
    device_sn VARCHAR(100),
    loc_country VARCHAR(100),
    loc_name VARCHAR(200),
    loc_lat DOUBLE PRECISION,
    loc_lon DOUBLE PRECISION,
    reading_count BIGINT,
    avg_radiation DOUBLE PRECISION,
    max_radiation DOUBLE PRECISION,
    min_radiation DOUBLE PRECISION,
    avg_temp DOUBLE PRECISION,
    max_temp DOUBLE PRECISION,
    min_temp DOUBLE PRECISION,

    PRIMARY KEY (day, device_urn)
);

CREATE INDEX IF NOT EXISTS idx_daily_day ON daily_summary(day);
CREATE INDEX IF NOT EXISTS idx_daily_device ON daily_summary(device_urn);

-- Function to refresh hourly summary
-- Call this after inserting new measurements
CREATE OR REPLACE FUNCTION refresh_hourly_summary()
RETURNS void AS $$
BEGIN
    -- Delete old data
    DELETE FROM hourly_summary;

    -- Recalculate from measurements (last 30 days)
    INSERT INTO hourly_summary
    SELECT
        DATE_TRUNC('hour', when_captured) as hour,
        device_urn,
        MAX(device_sn) as device_sn,
        MAX(loc_country) as loc_country,
        MAX(loc_name) as loc_name,
        AVG(loc_lat) as loc_lat,
        AVG(loc_lon) as loc_lon,
        COUNT(*) as reading_count,
        AVG(lnd_7318u::DOUBLE PRECISION) as avg_radiation,
        MAX(lnd_7318u::DOUBLE PRECISION) as max_radiation,
        MIN(lnd_7318u::DOUBLE PRECISION) as min_radiation,
        AVG(env_temp::DOUBLE PRECISION) as avg_temp,
        MAX(env_temp::DOUBLE PRECISION) as max_temp,
        MIN(env_temp::DOUBLE PRECISION) as min_temp
    FROM measurements
    WHERE when_captured >= NOW() - INTERVAL '30 days'
    GROUP BY hour, device_urn;
END;
$$ LANGUAGE plpgsql;

-- Function to refresh recent data
CREATE OR REPLACE FUNCTION refresh_recent_data()
RETURNS void AS $$
BEGIN
    DELETE FROM recent_data;

    INSERT INTO recent_data
    SELECT * FROM measurements
    WHERE when_captured >= NOW() - INTERVAL '7 days';
END;
$$ LANGUAGE plpgsql;

-- Function to refresh daily summary
CREATE OR REPLACE FUNCTION refresh_daily_summary()
RETURNS void AS $$
BEGIN
    DELETE FROM daily_summary;

    INSERT INTO daily_summary
    SELECT
        when_captured::DATE as day,
        device_urn,
        MAX(device_sn) as device_sn,
        MAX(loc_country) as loc_country,
        MAX(loc_name) as loc_name,
        AVG(loc_lat) as loc_lat,
        AVG(loc_lon) as loc_lon,
        COUNT(*) as reading_count,
        AVG(lnd_7318u::DOUBLE PRECISION) as avg_radiation,
        MAX(lnd_7318u::DOUBLE PRECISION) as max_radiation,
        MIN(lnd_7318u::DOUBLE PRECISION) as min_radiation,
        AVG(env_temp::DOUBLE PRECISION) as avg_temp,
        MAX(env_temp::DOUBLE PRECISION) as max_temp,
        MIN(env_temp::DOUBLE PRECISION) as min_temp
    FROM measurements
    GROUP BY day, device_urn;
END;
$$ LANGUAGE plpgsql;

-- Function to refresh all summaries
CREATE OR REPLACE FUNCTION refresh_all_summaries()
RETURNS void AS $$
BEGIN
    PERFORM refresh_hourly_summary();
    PERFORM refresh_recent_data();
    PERFORM refresh_daily_summary();
END;
$$ LANGUAGE plpgsql;

-- Grant permissions
GRANT ALL ON ALL TABLES IN SCHEMA public TO safecast;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO safecast;

-- Show table info
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;
