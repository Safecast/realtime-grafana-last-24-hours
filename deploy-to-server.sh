#!/bin/bash

# -----------------------------------------------------------------------------
# Script: deploy-to-server.sh
# Description: Deploy performance optimizations to production server
# Usage: ./deploy-to-server.sh
# -----------------------------------------------------------------------------

set -e

SERVER="root@grafana.safecast.jp"
SERVER_DIR="/home/grafana.safecast.jp/public_html"

echo "=========================================="
echo "Deploying to Production Server"
echo "=========================================="
echo ""

echo "Step 1: Pull latest code from GitHub on server..."
ssh $SERVER "cd $SERVER_DIR && git pull origin main"

echo ""
echo "Step 2: Create summary tables on server database..."
echo "This will create:"
echo "  - hourly_summary (hourly aggregations)"
echo "  - recent_data (last 7 days raw data)"
echo "  - daily_summary (daily aggregations)"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled."
    exit 1
fi

ssh $SERVER "cd $SERVER_DIR && chmod +x setup-summary-tables.sh && ./setup-summary-tables.sh"

echo ""
echo "Step 3: Configure passwordless sudo for Grafana restart..."
ssh $SERVER "cd $SERVER_DIR && chmod +x fix-cron-sudo.sh && ./fix-cron-sudo.sh"

echo ""
echo "Step 4: Update cron job with logging..."
echo "Current crontab on server:"
ssh $SERVER "crontab -l 2>/dev/null | grep -v '^#' | grep -v '^$'"
echo ""
echo "Recommended crontab entry:"
echo "*/5 * * * * cd $SERVER_DIR && ./update-with-restart.sh >> $SERVER_DIR/cron.log 2>&1"
echo ""
read -p "Update crontab now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    ssh $SERVER "crontab -l 2>/dev/null | grep -v update-with-restart > /tmp/crontab.tmp || true; echo '*/5 * * * * cd $SERVER_DIR && ./update-with-restart.sh >> $SERVER_DIR/cron.log 2>&1' >> /tmp/crontab.tmp; crontab /tmp/crontab.tmp; rm /tmp/crontab.tmp"
    echo "✅ Crontab updated"
else
    echo "⚠️  Skipped crontab update - you'll need to do this manually"
fi

echo ""
echo "Step 5: Test query performance on server..."
ssh $SERVER "cd $SERVER_DIR && duckdb /var/lib/grafana/data/devices.duckdb \"SELECT COUNT(*) FROM hourly_summary; SELECT COUNT(*) FROM recent_data; SELECT COUNT(*) FROM daily_summary;\""

echo ""
echo "=========================================="
echo "✅ Deployment Complete!"
echo "=========================================="
echo ""
echo "Summary tables created on server:"
echo "  - hourly_summary"
echo "  - recent_data"
echo "  - daily_summary"
echo ""
echo "Next steps:"
echo "  1. Wait 5 minutes for cron to run"
echo "  2. Check logs: ssh $SERVER 'tail -f $SERVER_DIR/cron.log'"
echo "  3. Update Grafana queries to use summary tables"
echo "  4. Test dashboard performance"
echo ""
echo "Grafana URL: https://grafana.safecast.jp"
echo ""
