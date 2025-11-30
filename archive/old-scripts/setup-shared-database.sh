#!/bin/bash

# -----------------------------------------------------------------------------
# Script: setup-shared-database.sh
# Description: Sets up a shared database location accessible by both
#              the data collection script (rob) and Grafana (grafana user)
# -----------------------------------------------------------------------------

set -e

echo "=========================================="
echo "DuckDB Shared Database Setup"
echo "=========================================="
echo ""

DB_DIR="/var/lib/grafana/data"
DB_PATH="$DB_DIR/devices.duckdb"
SOURCE_DB="/home/rob/Documents/realtime-grafana-last-24-hours/devices.duckdb"

echo "Creating shared database directory..."
sudo mkdir -p "$DB_DIR"

echo "Setting ownership to grafana user..."
sudo chown grafana:grafana "$DB_DIR"

echo "Setting permissions (grafana group can write)..."
sudo chmod 775 "$DB_DIR"

# Add rob to grafana group so he can write to the database
echo "Adding user 'rob' to 'grafana' group..."
sudo usermod -a -G grafana rob

echo ""
echo "✅ Directory setup complete: $DB_DIR"
echo ""

# Check if source database exists
if [ -f "$SOURCE_DB" ]; then
    echo "Found existing database at: $SOURCE_DB"
    echo "Copying to shared location..."

    sudo cp "$SOURCE_DB" "$DB_PATH"
    sudo chown grafana:grafana "$DB_PATH"
    sudo chmod 664 "$DB_PATH"

    echo "✅ Database copied successfully"

    # Show database info
    echo ""
    echo "Database information:"
    ls -lh "$DB_PATH"

else
    echo "No existing database found. A new one will be created on first run."
fi

echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "✅ Database location: $DB_PATH"
echo "✅ User 'rob' added to 'grafana' group"
echo ""
echo "⚠️  IMPORTANT: You need to log out and log back in for group changes to take effect!"
echo ""
echo "After logging back in, run:"
echo "  ./devices-last-24-hours.sh"
echo ""
echo "In Grafana, use this path for the DuckDB data source:"
echo "  $DB_PATH"
echo ""
