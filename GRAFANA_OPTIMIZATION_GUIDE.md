# Grafana Optimization Guide

This guide explains how to optimize your Grafana dashboards for different time ranges using the newly created summary tables and indexes.

## Summary of Optimization Strategy

| Time Range | Recommended Table | Update Frequency | Speed Rating |
|------------|-------------------|------------------|--------------|
| **Last 7 Days** | `recent_data` | Every 15 mins | ⚡⚡⚡ (Fastest) |
| **Last 30 Days** | `hourly_summary` | Every 15 mins | ⚡⚡ (Fast) |
| **Last 1 Year** | `daily_summary` | Daily | ⚡⚡ (Fast) |
| **Historical** | `measurements` | Real-time | 🐢 (Slowest) |

## 1. Optimizing "Last 7 Days" Dashboards

For detailed views of recent data, use the `recent_data` table. It contains raw measurements but is much smaller than the full history.

**Example Query:**
```sql
SELECT
  when_captured as time,
  device_urn,
  lnd_7318u as radiation
FROM recent_data
WHERE $__timeFilter(when_captured)
  AND device_urn IN ($device_urn)
ORDER BY time
```

## 2. Optimizing "Last 30 Days" Dashboards

For monthly trends, use `hourly_summary`. It aggregates data by hour, reducing row count by ~60x.

**Example Query:**
```sql
SELECT
  hour as time,
  device_urn,
  avg_radiation as radiation
FROM hourly_summary
WHERE $__timeFilter(hour)
  AND device_urn IN ($device_urn)
ORDER BY time
```

## 3. Optimizing "Last 1 Year" Dashboards

For long-term analysis, use `daily_summary`. It aggregates data by day, making year-long queries instant.

**Example Query:**
```sql
SELECT
  day as time,
  device_urn,
  avg_radiation as radiation
FROM daily_summary
WHERE $__timeFilter(day)
  AND device_urn IN ($device_urn)
ORDER BY time
```

## 4. Regular Database Indexing

Your database is automatically indexed by the data collection scripts. No manual action is needed.

**Indexes maintained:**
- `idx_when_captured`: Optimizes time-range queries.
- `idx_device_urn`: Optimizes device filtering.
- `idx_loc_country`: Optimizes geographic filtering.
- `idx_device_time`: Optimizes combined device + time queries.
- `idx_country_time`: Optimizes combined country + time queries.

## Troubleshooting

If queries feel slow:
1.  Check if you are using the correct table for the time range.
2.  Ensure your query uses `$__timeFilter()` or filters by indexed columns (`when_captured`, `device_urn`, `loc_country`).
3.  Run `./test-query-performance.sh` to verify index health.
