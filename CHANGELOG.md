# Changelog

## 2025-12-05 - Flip-Flop DuckDB Deployment

### Major Changes

#### 1. Flip-Flop Architecture Deployed
- Implemented dual-database system (`devices_a.duckdb`, `devices_b.duckdb`)
- Symlink `devices.duckdb` points to active database
- State tracked in `.active_db` file
- Grafana reads from symlink while updates write to inactive database

#### 2. update-flipflop-simple.sh Fixes
- **INSERT OR IGNORE**: Changed `INSERT INTO measurements` to `INSERT OR IGNORE INTO measurements` to handle duplicate records gracefully
- **Timestamp Format**: Changed from UTC (`date -u +'%Y-%m-%dT%H:%M:%SZ'`) to local time (`date +'%Y-%m-%d %H:%M:%S'`) to match existing data format
- **DELETE Disabled**: Commented out the DELETE statement that was removing data older than 30 days - all historical data is now preserved

#### 3. Grafana Dashboard (dashboard-motherduck.json)
- New dashboard using MotherDuck DuckDB datasource
- **Format Fix**: Changed `"format": "table"` to `"format": 1` (integer type required by plugin)
- **Time Macros**: Changed `$__timeFrom()` to `'${__from:date:iso}'` for proper SQL syntax
- **Type Casting**: Changed `CAST()` to `TRY_CAST()` to handle empty strings gracefully

### Server Configuration

| Setting | Value |
|---------|-------|
| Server | grafana.safecast.jp |
| DuckDB Version | v1.4.1 |
| Database Path | `/var/lib/grafana/data/` |
| Script Path | `/home/grafana.safecast.jp/public_html/` |
| Cron Schedule | Every 5 minutes |
| Datasource UID | `bf3xtqw2etaf4f` |

### Cron Job
```bash
*/5 * * * * cd /home/grafana.safecast.jp/public_html && ./update-flipflop-simple.sh >> /home/grafana.safecast.jp/public_html/flipflop.log 2>&1
```

### Database Optimizations
Added indexes for fast Grafana queries:
```sql
CREATE INDEX idx_device_urn ON measurements(device_urn);
CREATE INDEX idx_when_captured ON measurements(when_captured);
CREATE INDEX idx_device_time ON measurements(device_urn, when_captured);
```

### Historical Data Import
- Imported data from `devices_old.duckdb` (1.6GB)
- Total records: ~340,000+
- Date range: 2020-01-01 to present
- Note: Old data (2020-2024) is sparse (1-2 records per device per year)

### Files Modified
- `update-flipflop-simple.sh` - Core update script
- `dashboard-motherduck.json` - New Grafana dashboard
- `CHANGELOG.md` - This file

### Files on Server Only
- `/var/lib/grafana/data/devices_a.duckdb`
- `/var/lib/grafana/data/devices_b.duckdb`
- `/var/lib/grafana/data/devices.duckdb` (symlink)
- `/var/lib/grafana/data/.active_db` (state file)
- `/home/grafana.safecast.jp/public_html/flipflop.log` (log file)

### Monitoring Commands
```bash
# Check update log
tail -f /home/grafana.safecast.jp/public_html/flipflop.log

# Check active database
cat /var/lib/grafana/data/.active_db
ls -la /var/lib/grafana/data/devices.duckdb

# Check data count and range
./duckdb /var/lib/grafana/data/devices.duckdb "SELECT COUNT(*), MIN(when_captured), MAX(when_captured) FROM measurements WHERE when_captured < '2030-01-01';"
```
