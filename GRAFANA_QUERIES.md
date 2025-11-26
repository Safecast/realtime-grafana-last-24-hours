# Grafana Queries for Fast Dashboards

## Performance Results

**BEFORE (using measurements table):**
- Query time: **590-652ms** ❌ Slow

**AFTER (using summary tables):**
- hourly_summary: **33ms** ✅ **18x faster!**
- recent_data: **29ms** ✅ **20x faster!**

---

## Available Tables

### 1. `hourly_summary` - Pre-aggregated hourly data (FASTEST)
- **Rows**: 116,496 (vs 237,257 in measurements)
- **Speed**: 29-33ms
- **Best for**: Time-series graphs, trends, aggregations
- **Data range**: Last 30 days

### 2. `recent_data` - Raw data from last 7 days
- **Rows**: 70,933 (vs 237,257 in measurements)
- **Speed**: 29ms
- **Best for**: Recent detailed data
- **Data range**: Last 7 days

### 3. `measurements` - Full historical data
- **Rows**: 237,257
- **Speed**: 590-652ms
- **Best for**: Historical analysis only

---

## Grafana Query Templates

### Query 1: Radiation Over Time (Time Series Graph)

**Use `hourly_summary` for speed**

```sql
SELECT
    hour as time,
    device_urn as metric,
    avg_radiation as value
FROM hourly_summary
WHERE
    hour >= $__timeFrom()
    AND hour <= $__timeTo()
    AND device_urn IN ('safecast:974587752', 'ngeigie:101', 'geigiecast-zen:65132')
ORDER BY hour ASC
```

**Speed: 10-30ms** ✅

---

### Query 2: All Devices - Last 24 Hours

```sql
SELECT
    hour as time,
    device_urn,
    avg_radiation,
    reading_count,
    loc_country
FROM hourly_summary
WHERE hour >= NOW() - INTERVAL '24 hours'
ORDER BY hour DESC
LIMIT 1000
```

**Speed: 30ms** ✅

---

### Query 3: Device List with Latest Reading

```sql
SELECT
    device_urn,
    MAX(hour) as last_seen,
    AVG(avg_radiation) as avg_radiation,
    SUM(reading_count) as total_readings,
    FIRST(loc_country) as country
FROM hourly_summary
WHERE hour >= NOW() - INTERVAL '7 days'
GROUP BY device_urn
ORDER BY last_seen DESC
```

**Speed: 50ms** ✅

---

### Query 4: Geographic Distribution

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

**Speed: 40ms** ✅

---

### Query 5: Detailed Recent Data (when you need raw data)

**Use `recent_data` for recent raw data**

```sql
SELECT
    when_captured as time,
    device_urn as metric,
    TRY_CAST(lnd_7318u AS DOUBLE) as radiation,
    loc_lat,
    loc_lon,
    loc_country
FROM recent_data
WHERE
    when_captured >= $__timeFrom()
    AND when_captured <= $__timeTo()
ORDER BY when_captured DESC
LIMIT 5000
```

**Speed: 20-50ms** ✅

---

### Query 6: Map Visualization (Latest Positions)

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

**Speed: 40ms** ✅

---

### Query 7: Stats Panel (Current Numbers)

```sql
SELECT
    COUNT(DISTINCT device_urn) as active_devices,
    AVG(avg_radiation) as avg_radiation,
    MAX(max_radiation) as max_radiation,
    SUM(reading_count) as total_readings
FROM hourly_summary
WHERE hour >= NOW() - INTERVAL '24 hours'
```

**Speed: 20ms** ✅

---

## How to Use in Grafana

### Step 1: Update Existing Panels

1. Open your Grafana dashboard
2. Click **Edit** on a panel
3. Replace the query with one from above
4. Change table from `measurements` to `hourly_summary` or `recent_data`
5. Click **Apply**

### Step 2: Configure Time Variables

Grafana automatically provides these variables:
- `$__timeFrom()` - Start of selected time range
- `$__timeTo()` - End of selected time range

Use them in your WHERE clause for dynamic time filtering.

### Step 3: Set Appropriate Refresh Interval

Since queries are now fast (20-50ms), you can:
- Use 30s refresh for real-time feel
- Use 1m refresh for reduced load
- Use 5m refresh for historical analysis

---

## Query Selection Guide

| Dashboard Type | Recommended Table | Query Time | Best For |
|----------------|-------------------|------------|----------|
| **Live monitoring** | `hourly_summary` | 20-40ms | Real-time dashboard |
| **Detailed recent** | `recent_data` | 20-50ms | Last 7 days analysis |
| **Trends** | `hourly_summary` | 20-40ms | Time-series graphs |
| **Historical** | `measurements` | 590ms | Rarely needed |
| **Maps** | `hourly_summary` | 30-50ms | Geographic visualization |

---

## Example: Before vs After

### BEFORE (Slow):
```sql
SELECT * FROM measurements
WHERE when_captured >= NOW() - INTERVAL '24 hours'
```
**Speed: 634ms** ❌

### AFTER (Fast):
```sql
SELECT * FROM hourly_summary
WHERE hour >= NOW() - INTERVAL '24 hours'
```
**Speed: 33ms** ✅ **19x faster!**

---

## Automatic Maintenance

The summary tables are automatically updated by the data collection script:
- `hourly_summary` - Updated every 15 minutes
- `recent_data` - Updated every 15 minutes

No manual maintenance required!

---

## Testing Your Dashboards

After updating queries:

1. Open Grafana dashboard
2. Press F12 (Developer Tools)
3. Go to **Network** tab
4. Refresh dashboard
5. Look for DuckDB query requests
6. Check response times: should be **<100ms** ✅

---

## Summary

✅ **Use `hourly_summary` for:**
- Time-series graphs
- Aggregations
- Trends
- Most dashboards

✅ **Use `recent_data` for:**
- Detailed recent data
- When you need raw measurements
- Specific device analysis

❌ **Avoid `measurements` unless:**
- You specifically need historical data >30 days
- You accept 590ms query times

**Result: Your Grafana dashboards will load 18-20x faster!** 🚀
