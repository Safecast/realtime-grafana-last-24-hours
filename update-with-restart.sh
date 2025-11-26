#!/bin/bash
echo "Stopping Grafana..."
sudo systemctl stop grafana-server

echo "Running data update..."
./devices-last-24-hours.sh

echo "Starting Grafana..."
sudo systemctl start grafana-server

echo "Done!"
