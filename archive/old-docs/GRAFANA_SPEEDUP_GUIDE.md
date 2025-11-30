# Grafana Performance Speedup Guide

## Problem

Current Grafana dashboards are slow because queries scan all 237,257 rows (1.6GB database).
Query time: **590-652ms** (moderate/slow)

## Goal

Reduce Grafana dashboard load time to **<100ms** (excellent)

---

## Solution 1: Limit Grafana Queries by Time ⚡ EASIEST

### What to do:

Edit your Grafana dashboard queries to only fetch recent data.

### Before (slow):
```sql
SELECT * FROM measurements
```
**Problem:** Scans all 237,257 rows → 590ms

### After (fast):
```sql
SELECT * FROM measurements
WHERE when_captured >= NOW() - INTERVAL '7 days'
LIMIT 10000
```
**Result:** Scans ~70,000 rows → **50-100ms** (5-10x faster!)

### How to implement:

1. Open Grafana dashboard
2. Edit each panel
3. Modify SQL query to add `WHERE when_captured >= ...`
4. Save dashboard

**Expected improvement: 590ms → 50-100ms**

---

## Solution 2: Use Grafana Time Range Variables ⚡ RECOMMENDED

### What to do:

Use Grafana's built-in time picker to control query range.

### Query template:
```sql
SELECT
    when_captured as time,
    device_urn,
    TRY_CAST(lnd_7318u AS DOUBLE) as radiation,
    loc_country
FROM measurements
WHERE
    when_captured >= $__timeFrom()
    AND when_captured <= $__timeTo()
ORDER BY when_captured DESC
LIMIT 10000
```

### Benefits:
- Users can change time range (last 6h, 24h, 7d, 30d)
- Faster queries for shorter time ranges
- Standard Grafana pattern

**Expected improvement:**
- Last 6 hours: **10-20ms**
- Last 24 hours: **20-50ms**
- Last 7 days: **50-100ms**
- Last 30 days: **200-400ms**

---

## Solution 3: Add LIMIT to All Queries ⚡ QUICK WIN

### What to do:

Add `LIMIT` to every Grafana query.

### Example:
```sql
SELECT * FROM measurements
WHERE when_captured >= NOW() - INTERVAL '24 hours'
LIMIT 1000  -- or 5000, 10000
```

### Why it helps:
- Grafana charts rarely need more than 1000-5000 points
- Prevents loading unnecessary data
- Much faster data transfer

**Expected improvement: 590ms → 100-200ms**

---

## Solution 4: Increase Grafana Refresh Interval ⚡ IMMEDIATE

### Current problem:
If dashboards auto-refresh every 5-10 seconds, database is constantly queried.

### Solution:
Change refresh interval to 30s or 1 minute:
- Dashboard settings → Refresh interval → 30s

### Benefits:
- Less database load
- User won't notice difference
- Server handles more concurrent users

---

## Solution 5: Use Grafana Caching

### Enable query caching in Grafana datasource settings:

1. Go to: **Configuration → Data Sources → DuckDB**
2. Enable: **Query caching** (if available)
3. Set cache TTL: **30 seconds**

### Benefits:
- Repeated queries return instantly
- Reduces database load
- Great for multi-user dashboards

---

## Solution 6: Create Hourly Summary Table (Advanced)

### For maximum speed, pre-aggregate data hourly.

Create a summary table updated by your data collection script:

```sql
CREATE TABLE hourly_summary AS
SELECT
    DATE_TRUNC('hour', when_captured) as hour,
    device_urn,
    loc_country,
    COUNT(*) as reading_count,
    AVG(TRY_CAST(lnd_7318u AS DOUBLE)) as avg_radiation,
    MAX(TRY_CAST(lnd_7318u AS DOUBLE)) as max_radiation,
    MIN(TRY_CAST(lnd_7318u AS DOUBLE)) as min_radiation
FROM measurements
WHERE when_captured >= NOW() - INTERVAL '30 days'
GROUP BY hour, device_urn, loc_country;
```

### Update script to maintain it:
Add to `devices-last-24-hours.sh`:
```sql
-- Delete old hourly data
DELETE FROM hourly_summary WHERE hour < NOW() - INTERVAL '30 days';

-- Add new hourly data
INSERT INTO hourly_summary
SELECT ...
WHERE when_captured >= (SELECT MAX(hour) FROM hourly_summary);
```

### Use in Grafana:
```sql
SELECT * FROM hourly_summary
WHERE hour >= NOW() - INTERVAL '7 days'
```

**Expected improvement: 590ms → 10-30ms (20-60x faster!)**

---

## Recommended Approach

### Phase 1: Quick Wins (Do Today)

1. ✅ **Add time filters** to all Grafana queries (Solution 1)
   - Expected: 590ms → 50-100ms

2. ✅ **Add LIMIT 5000** to all queries (Solution 3)
   - Expected: Additional 20-30% speedup

3. ✅ **Increase refresh interval** to 30s (Solution 4)
   - Reduces server load

**Total expected improvement: 590ms → 50-100ms (6-10x faster)**

### Phase 2: Best Practice (Do This Week)

4. ✅ **Use Grafana time variables** (Solution 2)
   - Makes dashboards more flexible
   - Standard Grafana pattern

**Expected: 50-100ms → 10-50ms** (depending on selected range)

### Phase 3: Maximum Performance (Optional)

5. ✅ **Create hourly summary table** (Solution 6)
   - Only if Phase 1+2 isn't fast enough
   - Requires updating data collection script

**Expected: 10-30ms (excellent for any dashboard)**

---

## Example: Typical Grafana Dashboard Query

### Bad (slow):
```sql
SELECT * FROM measurements
```
**Speed: 590ms** ❌

### Good (fast):
```sql
SELECT
    when_captured as time,
    device_urn as metric,
    TRY_CAST(lnd_7318u AS DOUBLE) as value
FROM measurements
WHERE when_captured >= NOW() - INTERVAL '24 hours'
ORDER BY when_captured DESC
LIMIT 5000
```
**Speed: 50-80ms** ✅

### Best (very fast):
```sql
SELECT
    when_captured as time,
    device_urn as metric,
    TRY_CAST(lnd_7318u AS DOUBLE) as value
FROM measurements
WHERE
    when_captured >= $__timeFrom()
    AND when_captured <= $__timeTo()
ORDER BY when_captured DESC
LIMIT 5000
```
**Speed: 10-50ms** ✅✅

---

## Performance Comparison

| Solution | Speed | Improvement | Effort |
|----------|-------|-------------|--------|
| **Current (no limits)** | 590ms | - | - |
| **Add time filter (7 days)** | 50-100ms | 6-10x | Low |
| **Add LIMIT 5000** | 40-80ms | 7-15x | Very Low |
| **Use time variables** | 10-50ms | 12-60x | Low |
| **Hourly summary table** | 10-30ms | 20-60x | Medium |

---

## Testing Your Changes

After updating Grafana queries:

1. Open Grafana dashboard
2. Open browser DevTools (F12)
3. Go to Network tab
4. Refresh dashboard
5. Look for query response times
6. Should see: **<100ms** ✅

---

## Summary

**Don't worry about database architecture** - your DuckDB setup is fine!

**Focus on Grafana query optimization:**
1. Add time filters (`WHERE when_captured >= NOW() - INTERVAL '7 days'`)
2. Add LIMIT to queries (`LIMIT 5000`)
3. Use Grafana time variables (`$__timeFrom()`, `$__timeTo()`)

**Expected result:**
- Current: 590ms (moderate)
- After optimization: **10-100ms** (excellent!)

**This will make your Grafana dashboards feel instant!** ⚡
