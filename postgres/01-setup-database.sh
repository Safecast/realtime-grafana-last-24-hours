#!/bin/bash

# PostgreSQL Database Setup Script
# Creates database, user, and basic configuration

set -e

echo "=========================================="
echo "PostgreSQL Database Setup"
echo "=========================================="

# Configuration
DB_NAME="safecast"
DB_USER="safecast"
DB_PASSWORD="change_me_in_production"  # Change this!
DB_HOST="localhost"
DB_PORT="5432"

echo ""
echo "This script will create:"
echo "  - Database: $DB_NAME"
echo "  - User: $DB_USER"
echo "  - Password: $DB_PASSWORD (CHANGE THIS!)"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

# Check if PostgreSQL is installed
if ! command -v psql &> /dev/null; then
    echo "Error: PostgreSQL is not installed."
    echo ""
    echo "To install on Ubuntu/Debian:"
    echo "  sudo apt-get update"
    echo "  sudo apt-get install -y postgresql postgresql-contrib"
    echo ""
    echo "To install on macOS:"
    echo "  brew install postgresql"
    echo "  brew services start postgresql"
    exit 1
fi

# Check if PostgreSQL is running
if ! sudo systemctl is-active --quiet postgresql 2>/dev/null && ! pg_isready -h localhost &>/dev/null; then
    echo "PostgreSQL is not running. Starting..."
    sudo systemctl start postgresql || brew services start postgresql
    sleep 2
fi

# Create database and user
echo ""
echo "Creating database and user..."

sudo -u postgres psql <<EOF
-- Create user if not exists
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_user WHERE usename = '$DB_USER') THEN
        CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';
    END IF;
END
\$\$;

-- Create database if not exists
SELECT 'CREATE DATABASE $DB_NAME OWNER $DB_USER'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$DB_NAME')\gexec

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;

-- Connect to the database and grant schema privileges
\c $DB_NAME

GRANT ALL ON SCHEMA public TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $DB_USER;

-- Show success
SELECT 'Database created successfully!' as status;
EOF

# Save connection info to a file
CONFIG_FILE="$(dirname "$0")/postgres-config.sh"
cat > "$CONFIG_FILE" <<EOF
# PostgreSQL Configuration
# Source this file in scripts: source postgres-config.sh

export PGHOST="$DB_HOST"
export PGPORT="$DB_PORT"
export PGDATABASE="$DB_NAME"
export PGUSER="$DB_USER"
export PGPASSWORD="$DB_PASSWORD"

# Connection string for psql
export DATABASE_URL="postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME"
EOF

chmod 600 "$CONFIG_FILE"

echo ""
echo "=========================================="
echo "✅ PostgreSQL Setup Complete!"
echo "=========================================="
echo ""
echo "Database: $DB_NAME"
echo "User: $DB_USER"
echo "Host: $DB_HOST"
echo "Port: $DB_PORT"
echo ""
echo "Configuration saved to: $CONFIG_FILE"
echo ""
echo "To connect manually:"
echo "  psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME"
echo ""
echo "Or source the config and connect:"
echo "  source $CONFIG_FILE"
echo "  psql"
echo ""
echo "⚠️  SECURITY: Change the password in production!"
echo "   ALTER USER $DB_USER WITH PASSWORD 'new_secure_password';"
echo ""
echo "Next step: Run 02-create-schema.sh"
echo "=========================================="
