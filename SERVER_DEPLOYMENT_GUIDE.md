# Server Deployment Guide

## What Will Be Changed on the Server

### Database Structure Changes

**New Tables Created:**
1. **`hourly_summary`** - Hourly aggregated data
   - Columns: hour, device_urn, device_sn, loc_country, loc_name, loc_lat, loc_lon, reading_count, avg_radiation, max_radiation, min_radiation, avg_temp, max_temp, min_temp
   - Indexes: idx_hourly_hour, idx_hourly_device, idx_hourly_country, idx_hourly_device_hour
   - Purpose: Fast queries for time-series graphs (30-50ms)

2. **`recent_data`** - Last 7 days raw data
   - Columns: Same as measurements table
   - Indexes: idx_recent_when, idx_recent_device, idx_recent_country
   - Purpose: Fast queries for recent detailed data (20-50ms)

3. **`daily_summary`** - Daily aggregated data (all history)
   - Columns: day, device_urn, device_sn, loc_country, loc_name, loc_lat, loc_lon, reading_count, avg_radiation, max_radiation, min_radiation, avg_temp, max_temp, min_temp
   - Indexes: idx_daily_day, idx_daily_device, idx_daily_country
   - Purpose: Fast queries for long-term trends (50-100ms)

**Existing Table Enhanced:**
- **`measurements`** - Performance indexes added
  - New indexes: idx_when_captured, idx_device_urn, idx_loc_country, idx_device_time, idx_country_time
  - Purpose: Faster queries even on main table

**No Data Loss:**
- Original `measurements` table is NOT modified (data preserved)
- Summary tables are created FROM measurements data
- All data remains accessible

---

## Deployment Steps

### Option 1: Automated Deployment (Recommended)

Run the deployment script:

```bash
cd ~/Documents/realtime-grafana-last-24-hours
./deploy-to-server.sh
```

This will:
1. Pull latest code from GitHub
2. Create summary tables on server database
3. Configure passwordless sudo for cron
4. Update cron job with logging

### Option 2: Manual Deployment

**Step 1: SSH to server**
```bash
ssh root@grafana.safecast.jp
cd /home/grafana.safecast.jp/public_html
```

**Step 2: Pull latest code**
```bash
git pull origin main
```

**Step 3: Create summary tables**
```bash
chmod +x setup-summary-tables.sh
./setup-summary-tables.sh
```

**Expected output:**
```
✅ hourly_summary table created with indexes
✅ recent_data table created with indexes
✅ daily_summary table created with indexes

Tables created:
  1. hourly_summary   - Hourly aggregations (last 30 days)
  2. recent_data      - Raw data (last 7 days)
  3. daily_summary    - Daily aggregations (all history)
```

**Step 4: Configure passwordless sudo**
```bash
chmod +x fix-cron-sudo.sh
./fix-cron-sudo.sh
```

**Step 5: Update crontab**
```bash
crontab -e
```

Change:
```
*/15 * * * * cd /home/grafana.safecast.jp/public_html && ./devices-last-24-hours.sh
```

To:
```
*/15 * * * * cd /home/grafana.safecast.jp/public_html && ./update-with-restart.sh >> /home/grafana.safecast.jp/public_html/cron.log 2>&1
```

**Step 6: Wait and verify**
```bash
# Wait 15 minutes for cron to run
tail -f /home/grafana.safecast.jp/public_html/cron.log
```

---

## Database Changes Summary

### Before Deployment
```
measurements table:
  - 237,257 rows (1.6GB)
  - Query time: 590-650ms
  - Indexes: Basic PRIMARY KEY only
```

### After Deployment
```
measurements table:
  - 237,257 rows (unchanged)
  - Query time: 590ms (unchanged, use summary tables instead)
  - Indexes: Enhanced with 5 new performance indexes

hourly_summary table (NEW):
  - ~116,000 rows
  - Query time: 30-50ms (18x faster!)
  - Covers last 30 days

recent_data table (NEW):
  - ~71,000 rows
  - Query time: 20-50ms (20x faster!)
  - Covers last 7 days

daily_summary table (NEW):
  - ~6,000 rows
  - Query time: 10-30ms (50x faster!)
  - Covers all history
```

---

## Verification

### Check Tables Exist
```bash
ssh root@grafana.safecast.jp
cd /home/grafana.safecast.jp/public_html
duckdb /var/lib/grafana/data/devices.duckdb <<EOF
SELECT
    'measurements' as table_name,
    COUNT(*) as row_count
FROM measurements
UNION ALL
SELECT 'hourly_summary', COUNT(*) FROM hourly_summary
UNION ALL
SELECT 'recent_data', COUNT(*) FROM recent_data
UNION ALL
SELECT 'daily_summary', COUNT(*) FROM daily_summary;
EOF
```

### Test Query Performance
```bash
time duckdb /var/lib/grafana/data/devices.duckdb "SELECT * FROM hourly_summary WHERE hour >= NOW() - INTERVAL '24 hours' LIMIT 10;"
```

Should complete in **<50ms**.

### Check Cron Job
```bash
tail -f /home/grafana.safecast.jp/public_html/cron.log
```

Should see:
```
Stopping Grafana...
Running data update...
Updating summary tables...
Starting Grafana...
Done!
```

---

## Rollback (If Needed)

If something goes wrong, you can rollback:

**Remove summary tables:**
```bash
ssh root@grafana.safecast.jp
duckdb /var/lib/grafana/data/devices.duckdb <<EOF
DROP TABLE IF EXISTS hourly_summary;
DROP TABLE IF EXISTS recent_data;
DROP TABLE IF EXISTS daily_summary;
EOF
```

**Revert to old script:**
```bash
cd /home/grafana.safecast.jp/public_html
git checkout HEAD~1 devices-last-24-hours.sh
```

**Revert crontab:**
```bash
crontab -e
# Change back to:
*/15 * * * * cd /home/grafana.safecast.jp/public_html && ./devices-last-24-hours.sh
```

---

## Post-Deployment

### Update Grafana Queries

Replace slow queries with fast ones. See [GRAFANA_QUERIES.md](GRAFANA_QUERIES.md)

**Before (590ms):**
```sql
SELECT * FROM measurements
WHERE when_captured >= NOW() - INTERVAL '24 hours'
```

**After (33ms):**
```sql
SELECT * FROM hourly_summary
WHERE hour >= NOW() - INTERVAL '24 hours'
```

### Monitor Performance

Check Grafana dashboard load times:
- Open https://grafana.safecast.jp
- Press F12 → Network tab
- Query times should be **<100ms**

---

## Troubleshooting

### Summary tables don't exist
```bash
ssh root@grafana.safecast.jp
cd /home/grafana.safecast.jp/public_html
./setup-summary-tables.sh
```

### Cron not updating tables
```bash
# Check cron logs
tail -f /home/grafana.safecast.jp/public_html/cron.log

# Check crontab
crontab -l | grep update-with-restart

# Test manually
./update-with-restart.sh
```

### Sudo password prompts
```bash
./fix-cron-sudo.sh
```

---

## Expected Timeline

- Pull code: **30 seconds**
- Create summary tables: **2-5 minutes** (depends on database size)
- Configure sudo: **10 seconds**
- Update crontab: **30 seconds**
- First cron run: **15 minutes** (wait for next interval)
- Update Grafana queries: **10-30 minutes**

**Total deployment time: ~20-30 minutes**

---

## Success Criteria

✅ Summary tables exist on server
✅ Cron job runs without errors
✅ Cron log shows successful updates
✅ Grafana queries return in <100ms
✅ Dashboards load 18-20x faster

---

## Support

If you encounter issues:
1. Check [IMPLEMENTATION_COMPLETE.md](IMPLEMENTATION_COMPLETE.md)
2. Review [GRAFANA_SPEEDUP_GUIDE.md](GRAFANA_SPEEDUP_GUIDE.md)
3. Check server logs: `tail -f /home/grafana.safecast.jp/public_html/cron.log`
