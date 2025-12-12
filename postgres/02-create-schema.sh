#!/bin/bash

# Create PostgreSQL Schema
# Run this after 01-setup-database.sh

set -e

echo "=========================================="
echo "Creating PostgreSQL Schema"
echo "=========================================="

# Load configuration
CONFIG_FILE="$(dirname "$0")/postgres-config.sh"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file not found: $CONFIG_FILE"
    echo "Please run 01-setup-database.sh first"
    exit 1
fi

source "$CONFIG_FILE"

# Run schema creation
echo ""
echo "Creating tables, indexes, and functions..."
psql -f "$(dirname "$0")/02-create-schema.sql"

echo ""
echo "=========================================="
echo "✅ Schema Created Successfully!"
echo "=========================================="
echo ""
echo "Tables created:"
echo "  - measurements (main data)"
echo "  - hourly_summary (pre-aggregated)"
echo "  - recent_data (last 7 days)"
echo "  - daily_summary (pre-aggregated)"
echo ""
echo "Functions created:"
echo "  - refresh_hourly_summary()"
echo "  - refresh_recent_data()"
echo "  - refresh_daily_summary()"
echo "  - refresh_all_summaries()"
echo ""
echo "Indexes created for fast queries"
echo ""
echo "Next step: Run 03-migrate-data.sh to import existing DuckDB data"
echo "=========================================="
