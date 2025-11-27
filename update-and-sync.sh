#!/bin/bash

# Main update script: Update DuckLake then sync to Grafana

cd "$(dirname "$0")"

echo "=========================================="
echo "Starting DuckLake update pipeline"
echo "=========================================="

# Step 1: Update DuckLake (no locking issues)
./devices-last-24-hours-ducklake.sh

if [ $? -ne 0 ]; then
    echo "❌ DuckLake update failed. Aborting."
    exit 1
fi

# Step 2: Incremental sync to Grafana DB (fast, <1 second)
./sync-incremental.sh

if [ $? -eq 0 ]; then
    echo ""
    echo "=========================================="
    echo "✅ Update pipeline complete!"
    echo "=========================================="
else
    echo "❌ Sync failed!"
    exit 1
fi
