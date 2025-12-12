#!/bin/bash

# Optional: TimescaleDB Setup
# Adds time-series optimizations to PostgreSQL
# Run this AFTER the basic PostgreSQL setup is working

set -e

echo "=========================================="
echo "TimescaleDB Setup (Optional Enhancement)"
echo "=========================================="

echo ""
echo "TimescaleDB adds:"
echo "  ✅ Automatic time-based partitioning"
echo "  ✅ Compression for old data (save disk space)"
echo "  ✅ Continuous aggregates (faster queries)"
echo "  ✅ Better time-series query performance"
echo ""
echo "Note: This is OPTIONAL. PostgreSQL already works great!"
echo "Only add TimescaleDB if you want these extra features."
echo ""
read -p "Continue with TimescaleDB installation? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Skipping TimescaleDB installation"
    exit 0
fi

# Check OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "Cannot detect OS. Please install TimescaleDB manually:"
    echo "  https://docs.timescale.com/install/latest/"
    exit 1
fi

# Install TimescaleDB
echo ""
echo "Installing TimescaleDB..."

case "$OS" in
    ubuntu|debian)
        echo "Installing for Ubuntu/Debian..."

        # Add TimescaleDB repository
        sudo sh -c "echo 'deb [signed-by=/usr/share/keyrings/timescale.keyring] https://packagecloud.io/timescale/timescaledb/ubuntu/ $(lsb_release -c -s) main' > /etc/apt/sources.list.d/timescaledb.list"

        wget --quiet -O - https://packagecloud.io/timescale/timescaledb/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/timescale.keyring

        sudo apt-get update
        sudo apt-get install -y timescaledb-2-postgresql-14  # Adjust version if needed

        # Tune PostgreSQL for TimescaleDB
        sudo timescaledb-tune --quiet --yes
        ;;

    darwin)
        echo "Installing for macOS..."
        brew tap timescale/tap
        brew install timescaledb
        ;;

    *)
        echo "Unsupported OS: $OS"
        echo "Please install manually: https://docs.timescale.com/install/latest/"
        exit 1
        ;;
esac

# Restart PostgreSQL
echo "Restarting PostgreSQL..."
sudo systemctl restart postgresql || brew services restart postgresql

sleep 2

# Load configuration
CONFIG_FILE="$(dirname "$0")/postgres-config.sh"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file not found"
    exit 1
fi

source "$CONFIG_FILE"

# Enable TimescaleDB extension
echo ""
echo "Enabling TimescaleDB extension..."

psql <<EOF
-- Enable TimescaleDB
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Verify installation
SELECT extname, extversion FROM pg_extension WHERE extname = 'timescaledb';
EOF

echo ""
echo "=========================================="
echo "Converting measurements table to hypertable..."
echo "=========================================="

# Convert measurements table to hypertable
psql <<EOF
-- Convert to hypertable (partitioned by time)
-- This must be done BEFORE adding more data
SELECT create_hypertable(
    'measurements',
    'when_captured',
    if_not_exists => TRUE,
    migrate_data => TRUE
);

-- Show hypertable info
SELECT * FROM timescaledb_information.hypertables
WHERE hypertable_name = 'measurements';
EOF

echo ""
echo "Setting up compression..."

# Set up compression (saves disk space for old data)
psql <<EOF
-- Enable compression
ALTER TABLE measurements SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'device_urn'
);

-- Add compression policy (compress data older than 7 days)
SELECT add_compression_policy('measurements', INTERVAL '7 days');

-- Show compression settings
SELECT * FROM timescaledb_information.compression_settings
WHERE hypertable_name = 'measurements';
EOF

echo ""
echo "Creating continuous aggregates..."

# Create continuous aggregates (auto-updating materialized views)
psql <<EOF
-- Drop old summary tables (we'll replace with continuous aggregates)
DROP TABLE IF EXISTS hourly_summary CASCADE;
DROP TABLE IF EXISTS daily_summary CASCADE;

-- Create hourly continuous aggregate
CREATE MATERIALIZED VIEW hourly_summary
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 hour', when_captured) AS hour,
    device_urn,
    device_sn,
    loc_country,
    loc_name,
    loc_lat,
    loc_lon,
    COUNT(*) as reading_count,
    AVG(lnd_7318u::DOUBLE PRECISION) as avg_radiation,
    MAX(lnd_7318u::DOUBLE PRECISION) as max_radiation,
    MIN(lnd_7318u::DOUBLE PRECISION) as min_radiation,
    AVG(env_temp::DOUBLE PRECISION) as avg_temp,
    MAX(env_temp::DOUBLE PRECISION) as max_temp,
    MIN(env_temp::DOUBLE PRECISION) as min_temp
FROM measurements
GROUP BY hour, device_urn, device_sn, loc_country, loc_name, loc_lat, loc_lon;

-- Add refresh policy (auto-update every hour)
SELECT add_continuous_aggregate_policy('hourly_summary',
    start_offset => INTERVAL '3 hours',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour');

-- Create daily continuous aggregate
CREATE MATERIALIZED VIEW daily_summary
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 day', when_captured) AS day,
    device_urn,
    device_sn,
    loc_country,
    loc_name,
    loc_lat,
    loc_lon,
    COUNT(*) as reading_count,
    AVG(lnd_7318u::DOUBLE PRECISION) as avg_radiation,
    MAX(lnd_7318u::DOUBLE PRECISION) as max_radiation,
    MIN(lnd_7318u::DOUBLE PRECISION) as min_radiation,
    AVG(env_temp::DOUBLE PRECISION) as avg_temp,
    MAX(env_temp::DOUBLE PRECISION) as max_temp,
    MIN(env_temp::DOUBLE PRECISION) as min_temp
FROM measurements
GROUP BY day, device_urn, device_sn, loc_country, loc_name, loc_lat, loc_lon;

-- Add refresh policy (auto-update every day)
SELECT add_continuous_aggregate_policy('daily_summary',
    start_offset => INTERVAL '3 days',
    end_offset => INTERVAL '1 day',
    schedule_interval => INTERVAL '1 day');

-- Show continuous aggregates
SELECT * FROM timescaledb_information.continuous_aggregates;
EOF

echo ""
echo "Adding data retention policy (optional)..."

# Optional: Add retention policy to auto-delete old data
# Uncomment if you want to keep only last N days
# psql <<EOF
# -- Keep only last 365 days of raw data
# SELECT add_retention_policy('measurements', INTERVAL '365 days');
# EOF

echo ""
echo "Creating indexes on continuous aggregates..."

psql <<EOF
-- Indexes for hourly_summary
CREATE INDEX idx_hourly_hour ON hourly_summary(hour DESC);
CREATE INDEX idx_hourly_device ON hourly_summary(device_urn);

-- Indexes for daily_summary
CREATE INDEX idx_daily_day ON daily_summary(day DESC);
CREATE INDEX idx_daily_device ON daily_summary(device_urn);
EOF

echo ""
echo "=========================================="
echo "✅ TimescaleDB Setup Complete!"
echo "=========================================="

# Show final stats
psql <<EOF
-- Show hypertable info
\x on
SELECT
    hypertable_name,
    num_chunks,
    compression_enabled,
    pg_size_pretty(total_bytes) as total_size,
    pg_size_pretty(before_compression_total_bytes) as uncompressed_size
FROM timescaledb_information.hypertables
WHERE hypertable_name = 'measurements';

-- Show continuous aggregates
SELECT
    view_name,
    refresh_lag,
    refresh_interval
FROM timescaledb_information.continuous_aggregates;
\x off
EOF

echo ""
echo "Benefits enabled:"
echo "  ✅ Automatic time-based partitioning"
echo "  ✅ Compression for data older than 7 days"
echo "  ✅ Auto-updating hourly aggregates (refresh every hour)"
echo "  ✅ Auto-updating daily aggregates (refresh every day)"
echo ""
echo "What changed:"
echo "  - measurements is now a hypertable (partitioned by time)"
echo "  - hourly_summary is now a continuous aggregate (auto-updates)"
echo "  - daily_summary is now a continuous aggregate (auto-updates)"
echo "  - You no longer need to call refresh functions manually!"
echo ""
echo "Your Grafana queries will work the same way, but faster!"
echo ""
echo "Note: Update 04-devices-postgres.sh to remove manual summary refreshes"
echo "=========================================="
