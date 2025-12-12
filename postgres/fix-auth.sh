#!/bin/bash

# Fix PostgreSQL authentication for safecast user
# This script fixes the common "password authentication failed" error

echo "=========================================="
echo "PostgreSQL Authentication Fix"
echo "=========================================="

echo ""
echo "This will:"
echo "  1. Verify the safecast user exists"
echo "  2. Reset the password"
echo "  3. Update pg_hba.conf to allow password auth"
echo ""

# Reset the safecast user password
echo "Resetting safecast user password..."
sudo -u postgres psql <<EOF
-- Ensure user exists and set password
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_user WHERE usename = 'safecast') THEN
        CREATE USER safecast WITH PASSWORD 'change_me_in_production';
    ELSE
        ALTER USER safecast WITH PASSWORD 'change_me_in_production';
    END IF;
END
\$\$;

-- Show user
\du safecast
EOF

# Find PostgreSQL version and config directory
PG_VERSION=$(psql --version | grep -oP '\d+' | head -1)
PG_CONFIG_DIR="/etc/postgresql/$PG_VERSION/main"

if [ ! -d "$PG_CONFIG_DIR" ]; then
    # Try to find config directory
    PG_CONFIG_DIR=$(find /etc/postgresql -name pg_hba.conf -exec dirname {} \; | head -1)
fi

echo ""
echo "PostgreSQL config directory: $PG_CONFIG_DIR"
echo ""

# Backup pg_hba.conf
echo "Backing up pg_hba.conf..."
sudo cp "$PG_CONFIG_DIR/pg_hba.conf" "$PG_CONFIG_DIR/pg_hba.conf.backup.$(date +%Y%m%d_%H%M%S)"

# Update pg_hba.conf to use md5 authentication for local connections
echo "Updating pg_hba.conf to allow password authentication..."

sudo bash -c "cat > $PG_CONFIG_DIR/pg_hba.conf.new" <<'EOF'
# PostgreSQL Client Authentication Configuration File
# Updated to allow password authentication

# TYPE  DATABASE        USER            ADDRESS                 METHOD

# "local" is for Unix domain socket connections only
local   all             postgres                                peer
local   all             safecast                                md5
local   all             all                                     peer

# IPv4 local connections:
host    all             all             127.0.0.1/32            md5

# IPv6 local connections:
host    all             all             ::1/128                 md5

# Allow replication connections from localhost
local   replication     all                                     peer
host    replication     all             127.0.0.1/32            md5
host    replication     all             ::1/128                 md5
EOF

sudo mv "$PG_CONFIG_DIR/pg_hba.conf.new" "$PG_CONFIG_DIR/pg_hba.conf"

# Restart PostgreSQL
echo ""
echo "Restarting PostgreSQL..."
sudo systemctl restart postgresql

sleep 2

# Test connection
echo ""
echo "Testing connection..."
export PGPASSWORD="change_me_in_production"
if psql -h localhost -U safecast -d safecast -c "SELECT 'Connection successful!' as status" 2>/dev/null; then
    echo ""
    echo "=========================================="
    echo "✅ Authentication Fixed!"
    echo "=========================================="
    echo ""
    echo "You can now run:"
    echo "  ./02-create-schema.sh"
    echo ""
else
    echo ""
    echo "❌ Still having issues. Please check:"
    echo "  1. PostgreSQL is running: sudo systemctl status postgresql"
    echo "  2. Config file: cat $PG_CONFIG_DIR/pg_hba.conf"
    echo "  3. PostgreSQL logs: sudo tail -50 /var/log/postgresql/postgresql-*.log"
fi
