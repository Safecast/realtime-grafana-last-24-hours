# Grafana PostgreSQL Data Source Setup

This guide shows how to configure Grafana to use PostgreSQL instead of DuckDB.

## Prerequisites

- PostgreSQL database set up (scripts 01-03 completed)
- Grafana installed and running
- Network access from Grafana to PostgreSQL

---

## Step 1: Add PostgreSQL Data Source

1. **Open Grafana** in your browser:
   - Local: http://localhost:3000
   - Server: https://grafana.safecast.jp

2. **Navigate to Data Sources**:
   - Click ⚙️ (Configuration) → Data sources
   - Click "Add data source"

3. **Select PostgreSQL**:
   - Search for "PostgreSQL"
   - Click on "PostgreSQL" (built-in, not a plugin!)

4. **Configure Connection**:

   | Field | Value | Notes |
   |-------|-------|-------|
   | Name | `Safecast Devices (PostgreSQL)` | Give it a descriptive name |
   | Host | `localhost:5432` | Or your PostgreSQL server address |
   | Database | `safecast` | From 01-setup-database.sh |
   | User | `safecast` | From 01-setup-database.sh |
   | Password | `your_password` | From postgres-config.sh |
   | TLS/SSL Mode | `disable` | For localhost; use `require` for remote |
   | Version | `14+` | Or your PostgreSQL version |
   | TimescaleDB | ☑️ Enable | If you ran 06-setup-timescaledb.sh |

5. **Save & Test**:
   - Click "Save & Test"
   - You should see: ✅ "Database Connection OK"

---

## Step 2: Update Existing Dashboard

If you have an existing dashboard using DuckDB/MotherDuck, you need to update it to use PostgreSQL.

### Option A: Update Data Source in Existing Dashboard

1. Open your dashboard
2. Click ⚙️ (Dashboard settings)
3. Click "JSON Model"
4. Find and replace all instances of the old datasource UID
5. Save

### Option B: Create New Dashboard

Use the example queries below to create panels.

---

## Step 3: Example Queries

### Query 1: Radiation Over Time (Last 24 Hours)

```sql
SELECT
  hour AS time,
  device_urn AS metric,
  avg_radiation AS value
FROM hourly_summary
WHERE
  hour >= $__timeFrom()
  AND hour <= $__timeTo()
ORDER BY hour ASC
```

**Panel Settings:**
- Visualization: Time series
- Format: Time series
- Unit: CPM (Counts Per Minute) or μSv/h

---

### Query 2: Device List with Latest Reading

```sql
SELECT
  device_urn,
  MAX(hour) as last_seen,
  AVG(avg_radiation) as avg_radiation,
  SUM(reading_count) as total_readings,
  MAX(loc_country) as country
FROM hourly_summary
WHERE hour >= NOW() - INTERVAL '7 days'
GROUP BY device_urn
ORDER BY last_seen DESC
```

**Panel Settings:**
- Visualization: Table
- Show: All data

---

### Query 3: Geographic Distribution

```sql
SELECT
  loc_country as country,
  COUNT(DISTINCT device_urn) as device_count,
  AVG(avg_radiation) as avg_radiation,
  SUM(reading_count) as total_readings
FROM hourly_summary
WHERE hour >= NOW() - INTERVAL '7 days'
GROUP BY loc_country
ORDER BY device_count DESC
```

**Panel Settings:**
- Visualization: Bar chart or Table
- Sort by: device_count

---

### Query 4: Map Visualization

```sql
SELECT DISTINCT ON (device_urn)
  device_urn,
  loc_lat as latitude,
  loc_lon as longitude,
  avg_radiation as value,
  hour as time,
  loc_country
FROM hourly_summary
WHERE hour >= NOW() - INTERVAL '24 hours'
ORDER BY device_urn, hour DESC
```

**Panel Settings:**
- Visualization: Geomap
- Latitude field: `latitude`
- Longitude field: `longitude`
- Value field: `value`

---

### Query 5: Real-time Statistics

```sql
SELECT
  COUNT(*) as total_measurements,
  COUNT(DISTINCT device_urn) as active_devices,
  MAX(when_captured) as last_update,
  AVG(lnd_7318u) as avg_radiation
FROM measurements
WHERE when_captured >= NOW() - INTERVAL '1 hour'
```

**Panel Settings:**
- Visualization: Stat
- Show: Current value
- Auto-refresh: 30s or 1m

---

## Step 4: Time Macros

Grafana PostgreSQL datasource supports these time macros:

| Macro | PostgreSQL Equivalent | Example |
|-------|----------------------|---------|
| `$__timeFrom()` | `'2024-01-01 00:00:00'::timestamp` | Start of time range |
| `$__timeTo()` | `'2024-01-02 00:00:00'::timestamp` | End of time range |
| `$__timeFilter(column)` | `column >= ... AND column <= ...` | Time range filter |
| `$__timeGroup(column, interval)` | `DATE_TRUNC('interval', column)` | Time grouping |

Example using time macros:
```sql
SELECT
  $__timeGroup(when_captured, '5m') as time,
  device_urn,
  AVG(lnd_7318u) as avg_radiation
FROM measurements
WHERE $__timeFilter(when_captured)
GROUP BY time, device_urn
ORDER BY time
```

---

## Step 5: Performance Tips

### Use Pre-Aggregated Tables

For best performance, use the summary tables:

| Table | Use Case | Time Range | Speed |
|-------|----------|------------|-------|
| `hourly_summary` | Most dashboards | Last 30 days | ⚡⚡⚡ Fastest |
| `daily_summary` | Long-term trends | All time | ⚡⚡ Fast |
| `recent_data` | Detailed view | Last 7 days | ⚡⚡ Fast |
| `measurements` | Raw data | All time | ⚡ Slower (but still fast!) |

### Enable Query Caching

In Grafana dashboard settings:
- Cache timeout: 30 seconds (for real-time) or 5 minutes (for historical)

### Auto-Refresh Settings

Recommended refresh intervals:
- Real-time dashboard: 30s or 1m
- Historical dashboard: 5m or disable

---

## Step 6: Variables (Optional)

Create dashboard variables for filtering:

### Device URN Variable

```sql
SELECT DISTINCT device_urn
FROM hourly_summary
WHERE hour >= NOW() - INTERVAL '7 days'
ORDER BY device_urn
```

**Usage in queries:**
```sql
SELECT * FROM hourly_summary
WHERE device_urn = '$device_urn'
```

### Country Variable

```sql
SELECT DISTINCT loc_country
FROM hourly_summary
WHERE hour >= NOW() - INTERVAL '7 days'
ORDER BY loc_country
```

---

## Step 7: Alerting (Optional)

Create alerts for high radiation levels:

```sql
SELECT
  device_urn,
  avg_radiation,
  loc_country,
  hour as time
FROM hourly_summary
WHERE
  hour >= NOW() - INTERVAL '1 hour'
  AND avg_radiation > 100  -- Threshold in CPM
```

**Alert Rule:**
- Condition: `avg_radiation > 100`
- Frequency: Every 5 minutes
- Notification: Email, Slack, etc.

---

## Step 8: Comparison with DuckDB

### Query Syntax Changes

| DuckDB | PostgreSQL | Notes |
|--------|-----------|-------|
| `DATE_TRUNC('hour', ts)` | `DATE_TRUNC('hour', ts)` | ✅ Same |
| `INTERVAL 7 DAY` | `INTERVAL '7 days'` | Note the plural and quotes |
| `NOW()` | `NOW()` | ✅ Same |
| `CAST(x AS BIGINT)` | `x::BIGINT` | Both work in PostgreSQL |
| `TRY_CAST()` | `CAST()` in `TRY-CATCH` | Use `NULLIF()` for safe casting |

### Example Migration

**DuckDB Query:**
```sql
SELECT * FROM hourly_summary
WHERE hour >= NOW() - INTERVAL 24 HOUR
```

**PostgreSQL Query:**
```sql
SELECT * FROM hourly_summary
WHERE hour >= NOW() - INTERVAL '24 hours'
```

The changes are minimal!

---

## Step 9: Remove Old DuckDB Data Source

Once everything is working:

1. Go to Configuration → Data sources
2. Find your old "MotherDuck" or "DuckDB" datasource
3. Click on it
4. Scroll down and click "Delete"
5. Confirm deletion

⚠️ **Make sure all dashboards are using PostgreSQL first!**

---

## Troubleshooting

### Connection Refused

**Error:** `connection refused`

**Fix:**
```bash
# Check if PostgreSQL is running
sudo systemctl status postgresql

# Check if it's listening on the right port
sudo netstat -tlnp | grep 5432

# Edit postgresql.conf if needed
sudo nano /etc/postgresql/14/main/postgresql.conf
# Set: listen_addresses = '*'

# Restart PostgreSQL
sudo systemctl restart postgresql
```

### Authentication Failed

**Error:** `password authentication failed for user "safecast"`

**Fix:**
```bash
# Reset password
sudo -u postgres psql
ALTER USER safecast WITH PASSWORD 'new_password';

# Update Grafana datasource with new password
```

### Permission Denied

**Error:** `permission denied for table measurements`

**Fix:**
```sql
-- Connect as postgres user
sudo -u postgres psql -d safecast

-- Grant permissions
GRANT ALL ON ALL TABLES IN SCHEMA public TO safecast;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO safecast;
```

### Slow Queries

**Issue:** Queries take >1 second

**Fix:**
```sql
-- Check if indexes exist
\d measurements

-- Recreate indexes if needed
CREATE INDEX IF NOT EXISTS idx_when_captured ON measurements(when_captured);
CREATE INDEX IF NOT EXISTS idx_device_urn ON measurements(device_urn);

-- Update statistics
ANALYZE measurements;
ANALYZE hourly_summary;

-- Consider TimescaleDB (06-setup-timescaledb.sh)
```

---

## Next Steps

1. ✅ Test all dashboard queries
2. ✅ Set up auto-refresh intervals
3. ✅ Configure alerts (optional)
4. ✅ Share dashboard with team
5. ⚙️ Deploy to production server (see 07-server-deployment.md)
6. 🚀 Optional: Add TimescaleDB for better performance (06-setup-timescaledb.sh)

---

## Support

- Grafana Docs: https://grafana.com/docs/grafana/latest/datasources/postgres/
- PostgreSQL Grafana Guide: https://grafana.com/grafana/plugins/postgres/
- TimescaleDB + Grafana: https://docs.timescale.com/use-timescale/latest/integrations/observability-alerting/grafana/
