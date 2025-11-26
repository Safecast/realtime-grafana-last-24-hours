# Performance Analysis: DuckDB vs PostgreSQL for Safecast Time-Series Data

## Current Situation

- **Database size**: 9.3MB (4,203 rows)
- **Devices**: 1,451 unique devices
- **Time range**: 2020-01-01 to 2025-11-06
- **Primary Key**: (device, when_captured)
- **Use case**: Analytical queries via Grafana dashboards

## Projected Growth

At 15-minute data collection intervals:
- **Per day**: ~139,000 readings (if all devices active)
- **Per week**: ~973,000 readings
- **To reach 1GB**: ~450,000 rows (approximately 3-4 days of full data)

## Performance Comparison: DuckDB vs PostgreSQL

### DuckDB (Current - Analytical Optimized)

**Strengths for your use case:**
- ✅ Column-oriented storage = excellent for aggregations
- ✅ Optimized for time-series analytics (MIN, MAX, AVG, GROUP BY)
- ✅ Vectorized execution = 10-100x faster than PostgreSQL for analytics
- ✅ Excellent compression = smaller file sizes
- ✅ Built-in Parquet support (with DuckLake)
- ✅ Perfect for Grafana dashboard queries

**Typical query performance (1GB+ database):**
- Time-range aggregation: **10-100ms**
- Full table scan: **100-500ms**
- Multi-device GROUP BY: **50-200ms**

**Weaknesses:**
- ❌ Poor concurrent write performance (solved by DuckLake)
- ❌ DuckLake catalog overhead for small queries

### PostgreSQL (Proposed - Transactional Optimized)

**Strengths:**
- ✅ Excellent concurrent read/write (no locking issues)
- ✅ Mature ecosystem
- ✅ Strong ACID guarantees
- ✅ Native PRIMARY KEY support

**Weaknesses for your use case:**
- ❌ Row-oriented storage = slower for analytical aggregations
- ❌ Requires careful index management for time-series performance
- ❌ Larger disk footprint for time-series data
- ❌ More complex setup (requires PostgreSQL server)
- ❌ Higher memory usage
- ❌ **10-100x SLOWER than DuckDB for analytical queries**

**Typical query performance (1GB+ database):**
- Time-range aggregation: **500ms - 5s** (without proper indexes)
- Full table scan: **2-10s**
- Multi-device GROUP BY: **1-10s**

## Root Causes of Slow Performance

Your slow performance with >1GB databases is likely caused by:

### 1. Missing Indexes on Query Columns

**Current schema:**
```sql
-- Only PRIMARY KEY (device, when_captured)
-- Missing: Index on when_captured alone
-- Missing: Index on device_urn
-- Missing: Index on loc_country
```

**Grafana typical queries:**
```sql
-- Time-range query (uses when_captured)
SELECT * FROM measurements
WHERE when_captured >= NOW() - INTERVAL '24 hours';

-- Device-specific query (uses device_urn)
SELECT * FROM measurements
WHERE device_urn = 'safecast:123456';

-- Geographic query (uses loc_country)
SELECT * FROM measurements
WHERE loc_country = 'Japan';
```

**Without proper indexes**, DuckDB must scan the entire table for these queries.

### 2. Grafana Plugin Query Inefficiency

The Grafana DuckDB plugin might be:
- Loading entire table into memory instead of using time-range filters
- Not pushing down WHERE clauses to DuckDB
- Opening new connections for each query (connection overhead)

### 3. DuckLake Catalog Overhead

DuckLake adds coordination overhead:
- SQLite catalog lookup for each query
- Parquet file resolution
- Transaction coordination

For small, frequent queries, this overhead can be noticeable.

### 4. Lack of Query Optimization

DuckDB benefits from:
- Partitioning large tables by date
- Statistics updates
- Proper data types (you're using VARCHAR for numeric fields)

## Recommended Solution

**DO NOT switch to PostgreSQL.** Instead:

### Phase 1: Optimize Current DuckDB Setup

1. **Add indexes for common query patterns**
2. **Partition data by date** (for >1GB tables)
3. **Optimize data types** (convert VARCHAR to proper numeric types)
4. **Enable statistics collection**
5. **Test with DuckLake on larger dataset**

### Phase 2: If Still Slow, Consider Hybrid Approach

Use **DuckDB + DuckLake + PostgreSQL catalog** (not pure PostgreSQL):
- PostgreSQL catalog = better concurrent coordination
- DuckDB + Parquet = fast analytical queries
- Best of both worlds

### Phase 3: If Performance Still Insufficient

Consider specialized time-series databases:
- **TimescaleDB** (PostgreSQL extension for time-series)
- **ClickHouse** (extremely fast analytics)
- **InfluxDB** (purpose-built for time-series)

## Performance Testing Script

Before making any architectural changes, test actual performance:

```bash
#!/bin/bash
# test-query-performance.sh

echo "Testing DuckDB query performance..."

time duckdb devices.duckdb "
SELECT
    device_urn,
    COUNT(*) as readings,
    AVG(lnd_7318u) as avg_radiation,
    MIN(when_captured) as first_reading,
    MAX(when_captured) as last_reading
FROM measurements
WHERE when_captured >= NOW() - INTERVAL '24 hours'
GROUP BY device_urn
ORDER BY readings DESC
LIMIT 100;
"

echo ""
echo "Testing with date range filter..."

time duckdb devices.duckdb "
SELECT COUNT(*) as total
FROM measurements
WHERE when_captured BETWEEN '2025-11-01' AND '2025-11-06';
"
```

Run this on your server database to see actual performance metrics.

## Migration Decision Matrix

| Scenario | Recommendation |
|----------|---------------|
| **Queries <500ms on 1GB database** | Keep DuckDB, optimize indexes |
| **Queries 500ms-2s on 1GB database** | Add DuckLake + PostgreSQL catalog |
| **Queries >2s on 1GB database** | Investigate Grafana plugin or consider TimescaleDB |
| **Need multi-user write concurrency** | DuckLake + PostgreSQL catalog |
| **Need ACID transactions** | DuckLake or PostgreSQL |
| **Analytics performance is critical** | **STAY WITH DUCKDB** |

## Bottom Line

**Switching to pure PostgreSQL will make your performance problem WORSE, not better.**

For analytical queries on time-series data:
- DuckDB: **10-100ms** per query
- PostgreSQL: **500ms-5s** per query (without expert tuning)

The performance issue you're anticipating is likely:
1. Missing indexes (easy fix)
2. Grafana plugin inefficiency (needs investigation)
3. DuckLake overhead for small queries (use PostgreSQL catalog)

**Recommended next steps:**
1. Run performance tests on actual server database
2. Add indexes for common query patterns
3. Monitor query performance with EXPLAIN ANALYZE
4. If still slow, add PostgreSQL catalog to DuckLake (not pure PostgreSQL)
5. Consider TimescaleDB only if DuckDB proves insufficient (unlikely)
