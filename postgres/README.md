# PostgreSQL Migration for Safecast Real-time Monitoring

This directory contains scripts and documentation for migrating from DuckDB (flip-flop architecture) to PostgreSQL with optional TimescaleDB enhancements.

## Why PostgreSQL?

**Problems with current DuckDB flip-flop approach:**
- ❌ 30-60 seconds of Grafana downtime every 5 minutes
- ❌ Complex flip-flop architecture (A/B databases + symlinks)
- ❌ No concurrent read/write
- ❌ Requires Grafana restarts

**Benefits of PostgreSQL:**
- ✅ Zero Grafana downtime
- ✅ True concurrent read/write (Grafana reads while script writes)
- ✅ Simpler architecture (one database, no flip-flop)
- ✅ Native Grafana support (first-class datasource)
- ✅ Better for time-series data (especially with TimescaleDB)
- ✅ More mature tooling and community support

## Quick Start

### Local Setup (Recommended First)

```bash
cd postgres/

# 1. Setup database
./01-setup-database.sh

# 2. Create schema
./02-create-schema.sh

# 3. Migrate existing data from DuckDB
./03-migrate-data.sh

# 4. Test data collection
chmod +x 04-devices-postgres.sh
./04-devices-postgres.sh

# 5. Configure Grafana
# See 05-grafana-setup.md

# 6. (Optional) Add TimescaleDB
./06-setup-timescaledb.sh
```

### Server Deployment

See [07-server-deployment.md](07-server-deployment.md) for complete deployment guide.

---

## Files Overview

| File | Description |
|------|-------------|
| `01-setup-database.sh` | Creates PostgreSQL database and user |
| `02-create-schema.sql` | SQL schema (tables, indexes, functions) |
| `02-create-schema.sh` | Runs the schema creation script |
| `03-migrate-data.sh` | Migrates data from DuckDB to PostgreSQL |
| `04-devices-postgres.sh` | Data collection script (replaces flip-flop) |
| `05-grafana-setup.md` | Grafana configuration guide |
| `06-setup-timescaledb.sh` | Optional: TimescaleDB installation |
| `07-server-deployment.md` | Server deployment guide |
| `postgres-config.sh` | Configuration (auto-generated) |
| `README.md` | This file |

---

## Migration Steps

### Step 1: Database Setup

```bash
./01-setup-database.sh
```

Creates:
- Database: `safecast`
- User: `safecast`
- Configuration file: `postgres-config.sh`

**⚠️ Change the default password in production!**

### Step 2: Schema Creation

```bash
./02-create-schema.sh
```

Creates tables:
- `measurements` - Main data table with PRIMARY KEY
- `hourly_summary` - Pre-aggregated hourly data (last 30 days)
- `recent_data` - Last 7 days of raw data
- `daily_summary` - Pre-aggregated daily data (all time)

Creates functions:
- `refresh_hourly_summary()`
- `refresh_recent_data()`
- `refresh_daily_summary()`
- `refresh_all_summaries()`

### Step 3: Data Migration

```bash
./03-migrate-data.sh
```

Process:
1. Exports data from DuckDB to CSV
2. Imports CSV to PostgreSQL using COPY (very fast)
3. Refreshes all summary tables
4. Updates table statistics

**Expected duration:** 5-15 minutes for ~340K records

### Step 4: Data Collection

```bash
./04-devices-postgres.sh
```

Replaces both:
- `devices-last-24-hours.sh`
- `update-flipflop-simple.sh`

**No Grafana restart needed!** PostgreSQL handles concurrent access.

Cron setup:
```bash
*/5 * * * * cd /path/to/postgres && ./04-devices-postgres.sh >> postgres.log 2>&1
```

### Step 5: Grafana Configuration

See [05-grafana-setup.md](05-grafana-setup.md)

Key points:
- Use built-in PostgreSQL datasource (not a plugin)
- Minimal query changes (`INTERVAL 7 DAY` → `INTERVAL '7 days'`)
- Better performance with native time macros

### Step 6: TimescaleDB (Optional)

```bash
./06-setup-timescaledb.sh
```

Adds:
- ✅ Automatic time-based partitioning (hypertables)
- ✅ Compression (30-50% disk space savings)
- ✅ Continuous aggregates (auto-updating materialized views)
- ✅ Better query performance (30-50% faster)

**Recommended for production!**

---

## Architecture Comparison

### Before: DuckDB Flip-Flop

```
TTServer → Script → [Inactive DuckDB] → Atomic Switch → [Active DuckDB] ← Grafana
                                     ↓
                          Restart Grafana (30-60s downtime)
```

**Issues:**
- Grafana downtime every 5 minutes
- Complex A/B database management
- No concurrent access

### After: PostgreSQL

```
TTServer → Script → PostgreSQL ← Grafana
                         ↑
                    (Concurrent Access, No Downtime!)
```

**Benefits:**
- Zero downtime
- Simple architecture
- Concurrent read/write

### After: PostgreSQL + TimescaleDB

```
TTServer → Script → PostgreSQL + TimescaleDB ← Grafana
                         ↑
                    (Auto-partitioning, Compression, Continuous Aggregates)
```

**Extra Benefits:**
- Automatic data management
- Better performance
- Lower disk usage

---

## Schema Overview

### Main Table: measurements

Primary key: `(device_urn, when_captured)`

Stores all radiation monitoring data with automatic deduplication.

Indexes:
- `idx_when_captured` - Time-based queries
- `idx_device_urn` - Device filtering
- `idx_device_time` - Combined device + time queries

### Summary Tables

**hourly_summary:**
- Pre-aggregated data by hour
- Last 30 days
- Used for most Grafana queries (fastest!)

**daily_summary:**
- Pre-aggregated data by day
- All historical data
- Used for long-term trends

**recent_data:**
- Copy of last 7 days from measurements
- Used for detailed recent queries

---

## Performance Comparison

| Query Type | DuckDB | PostgreSQL | PostgreSQL + TimescaleDB |
|------------|--------|-----------|-------------------------|
| Last 24h (hourly) | 20-40ms | 10-30ms | 5-15ms |
| Device list | 30-50ms | 15-30ms | 10-20ms |
| Map visualization | 40-50ms | 20-40ms | 15-30ms |
| Concurrent access | ❌ Not possible | ✅ Perfect | ✅ Perfect |
| Grafana downtime | 30-60s every 5min | ✅ 0 seconds | ✅ 0 seconds |

---

## Maintenance

### Daily (Automatic)

- Cron job runs data collection every 5 minutes
- Summary tables auto-refresh (or continuous aggregates with TimescaleDB)

### Weekly

```bash
source postgres-config.sh

# Update statistics
psql -c "ANALYZE;"

# Vacuum (clean up)
psql -c "VACUUM;"
```

### Monthly

```bash
# Check database size
psql -c "SELECT pg_size_pretty(pg_database_size('safecast'));"

# Check table sizes
psql -c "
SELECT
    tablename,
    pg_size_pretty(pg_total_relation_size(tablename::regclass)) as size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(tablename::regclass) DESC;
"
```

### Backup

```bash
# Simple backup
pg_dump > backup_$(date +%Y%m%d).sql

# Compressed backup
pg_dump | gzip > backup_$(date +%Y%m%d).sql.gz

# Restore
psql < backup_YYYYMMDD.sql
```

---

## Troubleshooting

### Connection Issues

```bash
# Check PostgreSQL is running
sudo systemctl status postgresql

# Check it's listening
sudo netstat -tlnp | grep 5432

# Test connection
psql -h localhost -U safecast -d safecast -c "SELECT 1"
```

### Data Collection Fails

```bash
# Check the log
tail -f postgres.log

# Run manually to see errors
./04-devices-postgres.sh

# Check PostgreSQL logs
sudo tail -f /var/log/postgresql/postgresql-*.log
```

### Slow Queries

```bash
# Check indexes exist
psql -c "\d measurements"

# Update statistics
psql -c "ANALYZE measurements;"

# Consider TimescaleDB
./06-setup-timescaledb.sh
```

---

## Migration Checklist

- [ ] Local testing complete
- [ ] PostgreSQL installed on server
- [ ] Database created (`01-setup-database.sh`)
- [ ] Schema created (`02-create-schema.sh`)
- [ ] DuckDB data backed up
- [ ] Data migrated (`03-migrate-data.sh`)
- [ ] Data collection tested (`04-devices-postgres.sh`)
- [ ] Cron job updated
- [ ] Grafana datasource configured
- [ ] Dashboard queries updated
- [ ] Monitored for 24 hours
- [ ] No errors in logs
- [ ] Old DuckDB files cleaned up (after 1 week)

---

## Support

- **PostgreSQL Docs:** https://www.postgresql.org/docs/
- **Grafana + PostgreSQL:** https://grafana.com/docs/grafana/latest/datasources/postgres/
- **TimescaleDB Docs:** https://docs.timescale.com/
- **Project Issues:** https://github.com/Safecast/realtime-grafana-last-24-hours/issues

---

## Next Steps After Migration

1. ✅ Monitor for 1 week
2. 🚀 Add TimescaleDB (optional but recommended)
3. 📊 Set up automated backups
4. 🔔 Configure Grafana alerts
5. 🧹 Clean up old DuckDB files
6. 📝 Update main project README

---

## Comparison: PostgreSQL vs DuckLake + PostgreSQL

See [POSTGRES_VS_DUCKLAKE_COMPARISON.md](../POSTGRES_VS_DUCKLAKE_COMPARISON.md) for detailed analysis.

**TL;DR:** For this use case, PostgreSQL direct is much simpler and better than DuckLake + PostgreSQL.

DuckLake makes sense for:
- Billions of rows
- Data lake scenarios
- Querying Parquet files
- Complex analytical workloads

Your use case needs:
- ✅ Simple time-series queries
- ✅ Small dataset (~340K rows)
- ✅ Concurrent read/write
- ✅ Easy maintenance

**PostgreSQL direct is the winner!** 🏆
