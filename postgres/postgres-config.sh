# PostgreSQL Configuration
# Source this file in scripts: source postgres-config.sh

export PGHOST="localhost"
export PGPORT="5432"
export PGDATABASE="safecast"
export PGUSER="safecast"
export PGPASSWORD="change_me_in_production"

# Connection string for psql
export DATABASE_URL="postgresql://safecast:change_me_in_production@localhost:5432/safecast"
