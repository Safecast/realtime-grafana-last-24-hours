#!/bin/bash

# -----------------------------------------------------------------------------
# Script: update-summary-with-restart.sh
# Description: Stops Grafana, updates summary tables, starts Grafana
# Usage: ./update-summary-with-restart.sh
# -----------------------------------------------------------------------------

echo "Stopping Grafana..."
sudo systemctl stop grafana-server

echo "Updating summary tables..."
./update-summary-tables.sh

echo "Starting Grafana..."
sudo systemctl start grafana-server

echo "Done!"
