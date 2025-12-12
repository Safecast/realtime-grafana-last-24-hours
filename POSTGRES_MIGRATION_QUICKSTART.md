# PostgreSQL Migration - Quick Start Guide

This is a step-by-step guide to migrate from DuckDB (flip-flop) to PostgreSQL.

## Why Migrate?

**Current Issues:**
- ❌ Grafana downtime: 30-60 seconds every 5 minutes
- ❌ Complex flip-flop architecture
- ❌ No concurrent read/write

**After Migration:**
- ✅ Zero Grafana downtime
- ✅ Simple architecture
- ✅ Concurrent access
- ✅ Better Grafana integration

## Quick Decision Guide

**Should you use:**

### PostgreSQL Direct? ✅ YES (RECOMMENDED)
- Simple time-series queries ✅
- Small dataset (<10M rows) ✅
- Want simplicity ✅
- Native Grafana support ✅

**Migration time:** 2-4 hours

### DuckLake + PostgreSQL? ❌ NO
- Complex setup ❌
- More components to manage ❌
- Overkill for your data size ❌

**Only use if:** Billions of rows, data lake scenarios, Parquet files

See [POSTGRES_VS_DUCKLAKE_COMPARISON.md](POSTGRES_VS_DUCKLAKE_COMPARISON.md) for detailed analysis.

---

## Migration Steps

### Step 1: Test Locally First (30 minutes)

```bash
cd postgres/

# Setup database
./01-setup-database.sh

# Create schema
./02-create-schema.sh

# Migrate data
./03-migrate-data.sh

# Test collection
./04-devices-postgres.sh

# Verify
source postgres-config.sh
psql -c "SELECT COUNT(*) FROM measurements"
```

### Step 2: Configure Local Grafana (15 minutes)

See [postgres/05-grafana-setup.md](postgres/05-grafana-setup.md)

1. Add PostgreSQL datasource
2. Update dashboard queries
3. Test all panels

### Step 3: Deploy to Server (1 hour)

See [postgres/07-server-deployment.md](postgres/07-server-deployment.md)

```bash
# On server
ssh root@grafana.safecast.jp
cd /home/grafana.safecast.jp/public_html/postgres

# Install PostgreSQL
sudo apt-get install postgresql

# Run setup
./01-setup-database.sh
./02-create-schema.sh
./03-migrate-data.sh

# Update cron
crontab -e
# Add: */5 * * * * cd .../postgres && ./04-devices-postgres.sh >> postgres.log 2>&1

# Configure Grafana datasource
```

### Step 4: Monitor (24 hours)

```bash
# Watch logs
tail -f postgres.log

# Check data
psql -c "SELECT MAX(when_captured) FROM measurements"
```

### Step 5: Optional Enhancements

```bash
# Add TimescaleDB (recommended)
./06-setup-timescaledb.sh
```

### Step 6: Cleanup (After 1 week)

```bash
# Remove old DuckDB files
sudo rm /var/lib/grafana/data/devices_a.duckdb
sudo rm /var/lib/grafana/data/devices_b.duckdb
```

---

## File Guide

| File | Purpose |
|------|---------|
| [postgres/README.md](postgres/README.md) | Complete documentation |
| [postgres/01-setup-database.sh](postgres/01-setup-database.sh) | Create database |
| [postgres/02-create-schema.sh](postgres/02-create-schema.sh) | Create tables |
| [postgres/03-migrate-data.sh](postgres/03-migrate-data.sh) | Migrate from DuckDB |
| [postgres/04-devices-postgres.sh](postgres/04-devices-postgres.sh) | New data collection |
| [postgres/05-grafana-setup.md](postgres/05-grafana-setup.md) | Grafana config |
| [postgres/06-setup-timescaledb.sh](postgres/06-setup-timescaledb.sh) | Optional: TimescaleDB |
| [postgres/07-server-deployment.md](postgres/07-server-deployment.md) | Server deployment |

---

## Expected Results

**Performance:**
- Queries: 10-30ms (vs 20-50ms)
- With TimescaleDB: 5-15ms
- Grafana downtime: 0 seconds! (vs 30-60s)

**Simplicity:**
- One database (vs two flip-flop databases)
- No symlinks
- No Grafana restarts

**Reliability:**
- Native PostgreSQL MVCC (concurrent access)
- Battle-tested technology
- Better tooling

---

## Need Help?

1. Check [postgres/README.md](postgres/README.md) for complete docs
2. Check [postgres/07-server-deployment.md](postgres/07-server-deployment.md) for troubleshooting
3. Review [POSTGRES_VS_DUCKLAKE_COMPARISON.md](POSTGRES_VS_DUCKLAKE_COMPARISON.md) for architecture details

---

## Success Checklist

- [ ] Local testing complete
- [ ] Grafana working locally
- [ ] Server PostgreSQL installed
- [ ] Data migrated successfully
- [ ] Cron job running
- [ ] Grafana dashboard updated
- [ ] No errors for 24 hours
- [ ] Old DuckDB removed (after 1 week)

**Ready to start? Run:** `cd postgres && ./01-setup-database.sh`
