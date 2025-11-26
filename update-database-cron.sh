#!/bin/bash

# -----------------------------------------------------------------------------
# Script: update-database-cron.sh
# Description: Updates database for cron - no Grafana restart needed!
# -----------------------------------------------------------------------------

cd /home/rob/Documents/realtime-grafana-last-24-hours

# Run data collection (updates measurements and summary tables)
./devices-last-24-hours.sh

# Exit with same code
exit $?
