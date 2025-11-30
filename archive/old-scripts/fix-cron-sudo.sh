#!/bin/bash

# -----------------------------------------------------------------------------
# Script: fix-cron-sudo.sh
# Description: Configure passwordless sudo for Grafana commands (for cron)
# Run this once: sudo ./fix-cron-sudo.sh
# -----------------------------------------------------------------------------

set -e

echo "=========================================="
echo "Configuring Passwordless Sudo for Grafana"
echo "=========================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Error: This script must be run with sudo"
    echo "Run: sudo ./fix-cron-sudo.sh"
    exit 1
fi

echo "Creating sudoers configuration for Grafana commands..."

# Create sudoers file
cat > /etc/sudoers.d/grafana-restart << 'EOF'
# Allow rob to restart grafana-server without password (for cron)
rob ALL=(ALL) NOPASSWD: /bin/systemctl stop grafana-server
rob ALL=(ALL) NOPASSWD: /bin/systemctl start grafana-server
rob ALL=(ALL) NOPASSWD: /bin/systemctl restart grafana-server
rob ALL=(ALL) NOPASSWD: /bin/systemctl status grafana-server
EOF

# Set correct permissions
chmod 440 /etc/sudoers.d/grafana-restart

# Validate sudoers syntax
echo "Validating sudoers syntax..."
if visudo -c -f /etc/sudoers.d/grafana-restart; then
    echo "✅ Sudoers configuration valid"
else
    echo "❌ Error: Invalid sudoers syntax"
    rm /etc/sudoers.d/grafana-restart
    exit 1
fi

echo ""
echo "=========================================="
echo "✅ Configuration Complete!"
echo "=========================================="
echo ""
echo "User 'rob' can now run these commands without password:"
echo "  - sudo systemctl stop grafana-server"
echo "  - sudo systemctl start grafana-server"
echo "  - sudo systemctl restart grafana-server"
echo "  - sudo systemctl status grafana-server"
echo ""
echo "This allows the cron job to work properly."
echo ""
echo "Next: Update your crontab with logging:"
echo "  crontab -e"
echo ""
echo "Add this line:"
echo '  */5 * * * * cd /home/rob/Documents/realtime-grafana-last-24-hours && ./update-with-restart.sh >> /home/rob/Documents/realtime-grafana-last-24-hours/cron.log 2>&1'
echo ""
