# Grafana DuckDB Plugin Setup Guide

Complete guide to visualizing your Safecast device data in Grafana using the DuckDB data source plugin.

---

## Prerequisites

✅ **Grafana 12.1.1** - Already installed on your system
✅ **DuckDB database** - `devices.duckdb` (7.6 MB with 3,253 measurements)
✅ **Data collection script** - Running every 15 minutes via cron

---

## Step 1: Download the DuckDB Plugin

1. Visit the releases page: https://github.com/motherduckdb/grafana-duckdb-datasource/releases

2. Download the latest release for your system (Linux):
   ```bash
   cd /tmp
   wget https://github.com/motherduckdb/grafana-duckdb-datasource/releases/download/v<VERSION>/motherduck-duckdb-datasource-linux-amd64-<VERSION>.zip
   ```

3. Extract the plugin:
   ```bash
   unzip motherduck-duckdb-datasource-linux-amd64-<VERSION>.zip
   ```

---

## Step 2: Install the Plugin

1. **Find your Grafana plugins directory**:
   ```bash
   # Default location:
   /var/lib/grafana/plugins/

   # Or check your grafana.ini:
   grep "plugins" /etc/grafana/grafana.ini
   ```

2. **Copy the plugin** to the plugins directory:
   ```bash
   sudo cp -r motherduck-duckdb-datasource /var/lib/grafana/plugins/
   sudo chown -R grafana:grafana /var/lib/grafana/plugins/motherduck-duckdb-datasource
   ```

---

## Step 3: Configure Grafana to Allow Unsigned Plugins

1. **Edit Grafana configuration**:
   ```bash
   sudo nano /etc/grafana/grafana.ini
   ```

2. **Add this line** under the `[plugins]` section:
   ```ini
   [plugins]
   allow_loading_unsigned_plugins = motherduck-duckdb-datasource
   ```

3. **Restart Grafana**:
   ```bash
   sudo systemctl restart grafana-server
   sudo systemctl status grafana-server
   ```

---

## Step 4: Add DuckDB Data Source in Grafana

1. **Open Grafana** in your browser: http://localhost:3000

2. **Navigate to**: Configuration → Data Sources → Add data source

3. **Search for**: "DuckDB"

4. **Configure the connection**:
   - **Name**: `Safecast Devices`
   - **Path**: `/home/rob/Documents/realtime-grafana-last-24-hours/devices.duckdb`
   - **MotherDuck Token**: Leave empty (not using cloud)

5. **Click "Save & Test"** to verify the connection

---

## Step 5: Create Your First Query

### Query 1: Total Device Count
```sql
SELECT COUNT(DISTINCT device_urn) as device_count
FROM measurements;
```

### Query 2: Recent Device Activity (Time Series)
```sql
SELECT
  DATE_TRUNC('hour', when_captured) as time,
  COUNT(DISTINCT device_urn) as active_devices
FROM measurements
WHERE $__timeFilter(when_captured)
GROUP BY 1
ORDER BY 1;
```

### Query 3: Radiation Readings by Device
```sql
SELECT
  device_urn,
  AVG(lnd_7318u) as avg_radiation,
  COUNT(*) as reading_count
FROM measurements
WHERE lnd_7318u > 0
  AND $__timeFilter(when_captured)
GROUP BY device_urn
ORDER BY avg_radiation DESC
LIMIT 10;
```

### Query 4: Air Quality (PM2.5) by Location
```sql
SELECT
  loc_country,
  loc_lat,
  loc_lon,
  AVG(CAST(pms_pm02_5 AS DOUBLE)) as avg_pm25
FROM measurements
WHERE pms_pm02_5 != '0'
  AND $__timeFilter(when_captured)
GROUP BY loc_country, loc_lat, loc_lon;
```

### Query 5: Device Activity Map (for Geomap Panel)
```sql
SELECT
  device_urn,
  loc_lat as latitude,
  loc_lon as longitude,
  loc_country,
  COUNT(*) as measurement_count,
  MAX(when_captured) as last_seen,
  AVG(lnd_7318u) as avg_radiation
FROM measurements
WHERE loc_lat != 0 AND loc_lon != 0
  AND $__timeFilter(when_captured)
GROUP BY device_urn, loc_lat, loc_lon, loc_country;
```

---

## Step 6: Build Your Dashboard

### Panel Ideas

#### 1. **Stat Panel: Total Devices**
- **Query**: Query 1 (Total Device Count)
- **Visualization**: Stat
- **Display**: Show total number of unique devices

#### 2. **Time Series: Active Devices Over Time**
- **Query**: Query 2 (Recent Device Activity)
- **Visualization**: Time series
- **Y-axis**: Number of active devices

#### 3. **Table: Top Radiation Readings**
- **Query**: Query 3 (Radiation by Device)
- **Visualization**: Table
- **Columns**: Device URN, Avg Radiation, Reading Count

#### 4. **Geomap: Device Locations**
- **Query**: Query 5 (Device Activity Map)
- **Visualization**: Geomap
- **Settings**:
  - Map view: World
  - Layer: Markers
  - Latitude field: `latitude`
  - Longitude field: `longitude`
  - Size: Based on `measurement_count`
  - Color: Based on `avg_radiation`

#### 5. **Time Series: Radiation Levels**
```sql
SELECT
  DATE_TRUNC('hour', when_captured) as time,
  device_urn,
  AVG(lnd_7318u) as radiation
FROM measurements
WHERE lnd_7318u > 0
  AND $__timeFilter(when_captured)
GROUP BY 1, 2
ORDER BY 1;
```
- **Visualization**: Time series
- **Legend**: Show device URNs

---

## Useful Grafana Macros

| Macro | Description | Example |
|-------|-------------|---------|
| `$__timeFilter(column)` | Filters by dashboard time range | `WHERE $__timeFilter(when_captured)` |
| `$__timeFrom` | Start of time range | `WHERE when_captured >= $__timeFrom` |
| `$__timeTo` | End of time range | `WHERE when_captured <= $__timeTo` |
| `$__interval` | Auto-calculated grouping interval | `DATE_TRUNC('$__interval', when_captured)` |

---

## Advanced Queries

### Detect Devices With High Radiation Anomalies
```sql
WITH device_stats AS (
  SELECT
    device_urn,
    AVG(lnd_7318u) as avg_radiation,
    STDDEV(lnd_7318u) as stddev_radiation
  FROM measurements
  WHERE lnd_7318u > 0
  GROUP BY device_urn
)
SELECT
  m.when_captured,
  m.device_urn,
  m.lnd_7318u,
  ds.avg_radiation,
  (m.lnd_7318u - ds.avg_radiation) / ds.stddev_radiation as z_score
FROM measurements m
JOIN device_stats ds ON m.device_urn = ds.device_urn
WHERE (m.lnd_7318u - ds.avg_radiation) / ds.stddev_radiation > 2
  AND $__timeFilter(m.when_captured)
ORDER BY m.when_captured DESC;
```

### Device Uptime Tracking
```sql
SELECT
  device_urn,
  MIN(when_captured) as first_seen,
  MAX(when_captured) as last_seen,
  COUNT(*) as total_readings,
  EXTRACT(EPOCH FROM (MAX(when_captured) - MIN(when_captured))) / 86400 as days_active
FROM measurements
WHERE $__timeFilter(when_captured)
GROUP BY device_urn
ORDER BY days_active DESC;
```

### Hourly Data Freshness Check
```sql
SELECT
  DATE_TRUNC('hour', when_captured) as time,
  COUNT(*) as readings_received
FROM measurements
WHERE when_captured >= NOW() - INTERVAL 24 HOURS
GROUP BY 1
ORDER BY 1;
```

---

## Troubleshooting

### Plugin Not Showing Up
1. Check plugin was extracted correctly:
   ```bash
   ls -la /var/lib/grafana/plugins/motherduck-duckdb-datasource/
   ```

2. Verify permissions:
   ```bash
   sudo chown -R grafana:grafana /var/lib/grafana/plugins/
   ```

3. Check Grafana logs:
   ```bash
   sudo journalctl -u grafana-server -f
   ```

### Connection Failed
1. Verify database file path is absolute
2. Check file permissions:
   ```bash
   ls -la /home/rob/Documents/realtime-grafana-last-24-hours/devices.duckdb
   ```
3. Make sure Grafana user can read the file:
   ```bash
   sudo chmod 644 /home/rob/Documents/realtime-grafana-last-24-hours/devices.duckdb
   ```

### Query Errors
- Ensure column names match your schema
- Use `TRY_CAST()` for type conversions
- Check for NULL values in calculations

---

## Data Schema Reference

Your `measurements` table schema:

```sql
CREATE TABLE measurements (
    bat_voltage VARCHAR,
    dev_temp BIGINT,
    device BIGINT,
    device_sn VARCHAR,
    device_urn VARCHAR,
    device_filename VARCHAR,
    env_temp BIGINT,
    lnd_7128ec VARCHAR,
    lnd_7318c VARCHAR,
    lnd_7318u BIGINT,
    loc_country VARCHAR,
    loc_lat DOUBLE,
    loc_lon DOUBLE,
    loc_name VARCHAR,
    pms_pm02_5 VARCHAR,
    when_captured TIMESTAMP,
    PRIMARY KEY (device, when_captured)
);
```

**Key Fields:**
- `device_urn`: Unique device identifier
- `when_captured`: Timestamp of measurement
- `lnd_7318u`, `lnd_7318c`, `lnd_7128ec`: Radiation sensor readings
- `pms_pm02_5`: Air quality PM2.5 readings
- `loc_lat`, `loc_lon`: GPS coordinates
- `bat_voltage`: Battery voltage
- `dev_temp`, `env_temp`: Temperature readings

---

## Alternative: Using Grafana's Infinity Plugin

If you have issues with the DuckDB plugin, you can export data to JSON periodically:

```bash
# Export to JSON (run this in cron after the main script)
duckdb devices.duckdb "
  COPY (
    SELECT * FROM measurements
    WHERE when_captured >= NOW() - INTERVAL 24 HOURS
  ) TO 'last-24-hours.json' (FORMAT JSON, ARRAY true);
"
```

Then use Grafana's Infinity data source to read the JSON file.

---

## Next Steps

1. ✅ Install the plugin
2. ✅ Configure the data source
3. ✅ Test with simple queries
4. ✅ Build your first dashboard
5. 📊 Share dashboards with your team
6. 🔔 Set up alerts for anomalies

---

## Resources

- **Plugin GitHub**: https://github.com/motherduckdb/grafana-duckdb-datasource
- **DuckDB Documentation**: https://duckdb.org/docs/
- **Grafana Dashboards**: https://grafana.com/docs/grafana/latest/dashboards/
- **Your Database**: `/home/rob/Documents/realtime-grafana-last-24-hours/devices.duckdb`

---

**Need Help?** Check the plugin's GitHub issues or Grafana community forums.
