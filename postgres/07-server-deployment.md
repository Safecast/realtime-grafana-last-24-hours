#!/bin/bash

# Server Deployment Guide: PostgreSQL Migration
# Deploy to grafana.safecast.jp

This guide walks through deploying the PostgreSQL-based system to your production server (grafana.safecast.jp).

## Overview

**What we're deploying:**
- PostgreSQL database on the server
- Migration of existing DuckDB data
- New data collection script (no flip-flop needed!)
- Updated Grafana datasource configuration
- Cron job for automatic updates every 5 minutes

**Benefits:**
- ✅ Zero Grafana downtime (no more 30-60s restarts!)
- ✅ Concurrent read/write (Grafana and script can run simultaneously)
- ✅ Simpler architecture (no flip-flop, no symlinks)
- ✅ Better performance with TimescaleDB (optional)
- ✅ Native Grafana support (better integration)

---

## Prerequisites

- SSH access to grafana.safecast.jp
- Root or sudo privileges
- Current DuckDB system running (for data migration)
- Git repository access

---

## Phase 1: Local Testing (RECOMMENDED)

Before deploying to production, test locally:

```bash
# On your local machine
cd /home/rob/Documents/realtime-grafana-last-24-hours/postgres

# Run setup scripts
./01-setup-database.sh
./02-create-schema.sh
./03-migrate-data.sh

# Test data collection
chmod +x 04-devices-postgres.sh
./04-devices-postgres.sh

# Verify in PostgreSQL
source postgres-config.sh
psql -c "SELECT COUNT(*) FROM measurements"

# Configure local Grafana (see 05-grafana-setup.md)
```

Once local testing is successful, proceed to server deployment.

---

## Phase 2: Server Deployment

### Step 1: Connect to Server

```bash
ssh root@grafana.safecast.jp
cd /home/grafana.safecast.jp/public_html
```

### Step 2: Pull Latest Code

```bash
# Ensure you're on the RT-postgress branch
git fetch origin
git checkout RT-postgress
git pull origin RT-postgress

# Verify postgres directory exists
ls -la postgres/
```

### Step 3: Install PostgreSQL

```bash
# Update package list
sudo apt-get update

# Install PostgreSQL
sudo apt-get install -y postgresql postgresql-contrib postgresql-client

# Check version
psql --version

# Verify it's running
sudo systemctl status postgresql
sudo systemctl enable postgresql  # Start on boot
```

### Step 4: Setup Database

```bash
cd /home/grafana.safecast.jp/public_html/postgres

# Make scripts executable
chmod +x *.sh

# Run database setup
./01-setup-database.sh
```

**IMPORTANT:** Change the default password!

```bash
# Edit the password in postgres-config.sh
nano postgres-config.sh

# Update PostgreSQL password
source postgres-config.sh
sudo -u postgres psql <<EOF
ALTER USER safecast WITH PASSWORD 'your_secure_password_here';
EOF
```

### Step 5: Create Schema

```bash
./02-create-schema.sh

# Verify tables were created
source postgres-config.sh
psql -c "\dt"
```

Expected output:
```
             List of relations
 Schema |      Name       | Type  |  Owner
--------+-----------------+-------+---------
 public | daily_summary   | table | safecast
 public | hourly_summary  | table | safecast
 public | measurements    | table | safecast
 public | recent_data     | table | safecast
```

### Step 6: Backup Existing DuckDB Data

**CRITICAL:** Backup before migration!

```bash
# Check current DuckDB setup
ls -la /var/lib/grafana/data/devices*.duckdb

# Backup both flip-flop databases
sudo cp /var/lib/grafana/data/devices_a.duckdb \
    /var/lib/grafana/data/backup_devices_a_$(date +%Y%m%d).duckdb

sudo cp /var/lib/grafana/data/devices_b.duckdb \
    /var/lib/grafana/data/backup_devices_b_$(date +%Y%m%d).duckdb

# Verify backups
ls -lh /var/lib/grafana/data/backup*.duckdb
```

### Step 7: Migrate Data from DuckDB to PostgreSQL

```bash
# Run migration script
./03-migrate-data.sh
```

This will:
1. Export all data from DuckDB to CSV
2. Import CSV into PostgreSQL
3. Refresh all summary tables
4. Verify data integrity

**Expected duration:** 5-15 minutes for ~340K records

Verify migration:
```bash
source postgres-config.sh

# Check record counts
psql -c "
SELECT
    'Measurements' as table_name,
    COUNT(*) as rows,
    MIN(when_captured) as oldest,
    MAX(when_captured) as newest
FROM measurements;
"

# Compare with DuckDB count
duckdb /var/lib/grafana/data/devices.duckdb \
    "SELECT COUNT(*) FROM measurements"
```

The counts should match!

### Step 8: Test Data Collection Script

```bash
# Test the new PostgreSQL data collection
./04-devices-postgres.sh
```

Expected output:
```
==========================================
Safecast Data Collection (PostgreSQL)
==========================================
Fetching device data from TTServer API...
Fetched 1456 device records
Converting JSON to CSV...
Inserting data into PostgreSQL...
Refreshing summary tables...
==========================================
✅ Data Collection Complete!
==========================================
```

Verify new data was added:
```bash
source postgres-config.sh
psql -c "SELECT MAX(when_captured) FROM measurements"
```

### Step 9: Update Cron Job

```bash
# Edit crontab
crontab -e

# Comment out old flip-flop script
# */5 * * * * cd /home/grafana.safecast.jp/public_html && ./update-flipflop-simple.sh >> /home/grafana.safecast.jp/public_html/flipflop.log 2>&1

# Add new PostgreSQL script
*/5 * * * * cd /home/grafana.safecast.jp/public_html/postgres && ./04-devices-postgres.sh >> /home/grafana.safecast.jp/public_html/postgres.log 2>&1

# Save and exit
```

Verify cron job:
```bash
crontab -l
```

### Step 10: Configure Grafana Data Source

1. **Open Grafana:** https://grafana.safecast.jp

2. **Add PostgreSQL Data Source:**
   - Go to Configuration → Data Sources
   - Click "Add data source"
   - Select "PostgreSQL"

3. **Configure:**
   ```
   Name: Safecast Devices (PostgreSQL)
   Host: localhost:5432
   Database: safecast
   User: safecast
   Password: [your password from postgres-config.sh]
   TLS/SSL Mode: disable (localhost)
   Version: 14+
   ```

4. **Save & Test:**
   - Click "Save & test"
   - Should see: ✅ "Database Connection OK"

### Step 11: Update Dashboard

See [05-grafana-setup.md](05-grafana-setup.md) for:
- Converting queries from DuckDB to PostgreSQL syntax
- Example queries for each panel
- Performance optimization tips

**Quick migration:**
- `INTERVAL 7 DAY` → `INTERVAL '7 days'`
- `TRY_CAST()` → `CAST()` or `::`
- Most queries work as-is!

### Step 12: Monitor for 24 Hours

```bash
# Watch the log
tail -f /home/grafana.safecast.jp/public_html/postgres.log

# Check cron is running
grep CRON /var/log/syslog | tail -20

# Check data is being added
source postgres/postgres-config.sh
psql -c "
SELECT
    MAX(when_captured) as last_update,
    COUNT(*) as total_records,
    COUNT(DISTINCT device_urn) as active_devices
FROM measurements;
"
```

Run this every few hours to ensure data collection is working.

### Step 13: Optional - Install TimescaleDB

For better performance (automatic partitioning, compression, continuous aggregates):

```bash
cd /home/grafana.safecast.jp/public_html/postgres
./06-setup-timescaledb.sh
```

**Benefits:**
- 30-50% faster queries
- Automatic compression (saves disk space)
- Auto-updating aggregates (no manual refresh needed)
- Better for large datasets

---

## Phase 3: Verification & Cleanup

### Verification Checklist

- [ ] PostgreSQL installed and running
- [ ] Database and schema created
- [ ] Data migrated (counts match)
- [ ] Test data collection successful
- [ ] Cron job installed and running
- [ ] Grafana datasource configured and tested
- [ ] Dashboard queries updated and working
- [ ] No errors in postgres.log for 24 hours
- [ ] Data is updating every 5 minutes

### Performance Comparison

Monitor query performance in Grafana:

**Before (DuckDB with flip-flop):**
- Grafana downtime: 30-60s every 5 minutes
- Query speed: 20-50ms (hourly_summary)
- Concurrent access: ❌ Not possible

**After (PostgreSQL):**
- Grafana downtime: ✅ 0 seconds!
- Query speed: 10-30ms (with indexes)
- Concurrent access: ✅ Perfect

**After (PostgreSQL + TimescaleDB):**
- Grafana downtime: ✅ 0 seconds!
- Query speed: 5-15ms (continuous aggregates)
- Concurrent access: ✅ Perfect
- Disk usage: 30-50% less (compression)

### Cleanup Old DuckDB Files (After 1 Week)

Once you're confident PostgreSQL is working:

```bash
# Keep backups!
ls -la /var/lib/grafana/data/backup*.duckdb

# Remove active flip-flop databases
sudo rm /var/lib/grafana/data/devices.duckdb  # Symlink
sudo rm /var/lib/grafana/data/devices_a.duckdb
sudo rm /var/lib/grafana/data/devices_b.duckdb
sudo rm /var/lib/grafana/data/.active_db

# Remove old logs
rm /home/grafana.safecast.jp/public_html/flipflop.log

# Remove old cron job (already done in Step 9)
```

---

## Phase 4: Monitoring & Maintenance

### Daily Monitoring

```bash
# Check database size
source postgres/postgres-config.sh
psql -c "
SELECT
    pg_size_pretty(pg_database_size('safecast')) as db_size;
"

# Check table sizes
psql -c "
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
"
```

### Weekly Maintenance

```bash
# Update table statistics (for query planner)
psql -c "ANALYZE;"

# Vacuum (clean up dead rows)
psql -c "VACUUM;"

# Or combined (more thorough, but locks tables briefly)
psql -c "VACUUM ANALYZE;"
```

### Monthly Tasks

```bash
# Check for slow queries
psql -c "
SELECT
    query,
    mean_exec_time,
    calls
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;
"

# Review disk usage trends
psql -c "SELECT pg_size_pretty(pg_database_size('safecast'));"
```

### Backup Strategy

**Option 1: Simple pg_dump (Good for daily backups)**

```bash
# Backup script
#!/bin/bash
source /home/grafana.safecast.jp/public_html/postgres/postgres-config.sh
pg_dump > /backups/safecast_$(date +%Y%m%d).sql
# Keep last 7 days
find /backups -name "safecast_*.sql" -mtime +7 -delete
```

**Option 2: Continuous Archiving (Better for production)**

Enable WAL archiving in postgresql.conf:
```
archive_mode = on
archive_command = 'cp %p /var/lib/postgresql/wal_archive/%f'
```

See: https://www.postgresql.org/docs/current/continuous-archiving.html

---

## Troubleshooting

### Data Collection Fails

```bash
# Check log
tail -50 /home/grafana.safecast.jp/public_html/postgres.log

# Test manually
cd /home/grafana.safecast.jp/public_html/postgres
./04-devices-postgres.sh

# Check PostgreSQL logs
sudo tail -50 /var/log/postgresql/postgresql-14-main.log
```

### Grafana Can't Connect

```bash
# Check PostgreSQL is listening
sudo netstat -tlnp | grep 5432

# Check pg_hba.conf allows local connections
sudo nano /etc/postgresql/14/main/pg_hba.conf
# Should have: local   all   all   md5

# Restart PostgreSQL
sudo systemctl restart postgresql
```

### Slow Queries

```bash
# Check if indexes exist
psql -c "\d measurements"

# Rebuild indexes
psql -c "REINDEX TABLE measurements;"

# Update statistics
psql -c "ANALYZE measurements;"

# Consider TimescaleDB
./06-setup-timescaledb.sh
```

### Disk Space Issues

```bash
# Check disk usage
df -h /var/lib/postgresql

# Vacuum to reclaim space
psql -c "VACUUM FULL;"

# Enable compression (TimescaleDB)
./06-setup-timescaledb.sh

# Or add retention policy
psql -c "
DELETE FROM measurements
WHERE when_captured < NOW() - INTERVAL '365 days';
VACUUM;
"
```

---

## Rollback Plan

If something goes wrong, you can rollback to DuckDB:

```bash
# Stop new cron job
crontab -e
# Comment out PostgreSQL cron job
# Uncomment flip-flop cron job

# Verify backup exists
ls -la /var/lib/grafana/data/backup*.duckdb

# Restore DuckDB
sudo cp /var/lib/grafana/data/backup_devices_a_YYYYMMDD.duckdb \
    /var/lib/grafana/data/devices_a.duckdb

sudo cp /var/lib/grafana/data/backup_devices_b_YYYYMMDD.duckdb \
    /var/lib/grafana/data/devices_b.duckdb

# Recreate symlink
echo "A" | sudo tee /var/lib/grafana/data/.active_db
sudo ln -sf devices_a.duckdb /var/lib/grafana/data/devices.duckdb

# Restore Grafana datasource to MotherDuck

# Test
./update-flipflop-simple.sh
```

---

## Success Metrics

After deployment, you should see:

- ✅ Data collection runs every 5 minutes (no errors in log)
- ✅ Grafana shows current data (within 5 minutes)
- ✅ No Grafana restarts (check with `systemctl status grafana-server`)
- ✅ Queries are fast (<50ms for hourly_summary)
- ✅ No database locking errors
- ✅ Dashboard works perfectly

**You've successfully migrated from DuckDB flip-flop to PostgreSQL!** 🎉

---

## Next Steps

1. Monitor for 1 week to ensure stability
2. Add TimescaleDB for better performance (optional)
3. Set up automated backups
4. Configure Grafana alerting (optional)
5. Clean up old DuckDB files
6. Update documentation

---

## Support Resources

- PostgreSQL Docs: https://www.postgresql.org/docs/
- Grafana + PostgreSQL: https://grafana.com/docs/grafana/latest/datasources/postgres/
- TimescaleDB Docs: https://docs.timescale.com/
- This Project: https://github.com/Safecast/realtime-grafana-last-24-hours/
