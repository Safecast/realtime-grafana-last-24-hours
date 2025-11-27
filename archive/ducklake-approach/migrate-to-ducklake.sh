#!/bin/bash

# -----------------------------------------------------------------------------
# Script: migrate-to-ducklake.sh
# Description: Selector script that calls the appropriate migration script
#              based on the environment (local or server)
# -----------------------------------------------------------------------------

echo "=========================================="
echo "DuckLake Migration Script Selector"
echo "=========================================="
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect environment
HOSTNAME=$(hostname)

if [[ "$HOSTNAME" == "rob-GS66-Stealth-10UG"* ]] || [[ "$HOSTNAME" == *"rob"* ]]; then
    echo "📍 Detected: LOCAL machine ($HOSTNAME)"
    echo "   Running: migrate-to-ducklake-local.sh"
    echo ""
    exec "$SCRIPT_DIR/migrate-to-ducklake-local.sh"
elif [[ "$HOSTNAME" == *"safecast"* ]] || [[ "$HOSTNAME" == "vps-01"* ]]; then
    echo "📍 Detected: SERVER ($HOSTNAME)"
    echo "   Running: migrate-to-ducklake-server.sh"
    echo ""
    exec "$SCRIPT_DIR/migrate-to-ducklake-server.sh"
else
    echo "⚠️  Cannot auto-detect environment: $HOSTNAME"
    echo ""
    echo "Please run the appropriate script manually:"
    echo "  Local:  ./migrate-to-ducklake-local.sh"
    echo "  Server: ./migrate-to-ducklake-server.sh"
    echo ""
    exit 1
fi
