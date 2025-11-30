# DuckLake Limitations and Solutions

## Important Limitation: No PRIMARY KEY Support

**Issue:** DuckLake does not support PRIMARY KEY or UNIQUE constraints as of version 0.3 (2025).

**Error you might see:**
```
Not implemented Error: PRIMARY KEY/UNIQUE constraints are not supported in DuckLake
```

---

## Our Solution: Deduplication at Insert Time

Instead of relying on database constraints, we handle deduplication in the application layer:

### Method Used in `devices-last-24-hours-ducklake.sh`:

```sql
-- Step 1: Load new data into temp table
CREATE TEMP TABLE new_measurements AS
SELECT DISTINCT ... FROM read_json_auto('data.json');

-- Step 2: Insert only new records (LEFT JOIN to find non-existent records)
INSERT INTO measurements
SELECT n.*
FROM new_measurements n
LEFT JOIN measurements m
    ON n.device = m.device
    AND n.when_captured = m.when_captured
WHERE m.device IS NULL;
```

**How it works:**
1. DISTINCT eliminates duplicates within the new batch
2. LEFT JOIN finds records that don't exist in the table yet
3. WHERE m.device IS NULL filters to only insert truly new records

---

## Performance Considerations

### Pro:
- ✅ Concurrent writes still work (no locking)
- ✅ ACID guarantees maintained
- ✅ Simple and reliable

### Con:
- ⚠️ Slight performance overhead from JOIN operation
- ⚠️ For large tables (millions of rows), deduplication query may be slower

### Optimization for Large Tables:

If your table grows very large (>1M rows), consider:

**Option 1: Partition by date**
```sql
-- Only check recent records (last 7 days)
LEFT JOIN measurements m
    ON n.device = m.device
    AND n.when_captured = m.when_captured
    AND m.when_captured >= CURRENT_DATE - INTERVAL 7 DAYS
```

**Option 2: Accept duplicates, deduplicate in queries**
```sql
-- In Grafana queries, use DISTINCT:
SELECT DISTINCT device_urn, when_captured, ...
FROM measurements
WHERE ...
```

**Option 3: Periodic cleanup**
```sql
-- Run weekly to remove duplicates:
CREATE TABLE measurements_deduped AS
SELECT DISTINCT * FROM measurements;

DROP TABLE measurements;
ALTER TABLE measurements_deduped RENAME TO measurements;
```

---

## Why This Still Works Well

Despite this limitation, DuckLake solves your main problem:

✅ **Concurrent Access** - Grafana and script work simultaneously (the key benefit!)
✅ **No Locking Errors** - Main issue is solved
✅ **Data Integrity** - Deduplication still works, just differently
✅ **Performance** - For your data volume (~2000 rows), overhead is negligible

---

## When Will PRIMARY KEY Be Supported?

DuckLake is under active development (currently v0.3). Check roadmap:
- GitHub: https://github.com/duckdb/ducklake
- Documentation: https://ducklake.select/

For updates, watch:
- DuckLake release notes
- DuckDB blog: https://duckdb.org/news

---

## Alternative: Use PostgreSQL Catalog

If you need true PRIMARY KEY constraints, use PostgreSQL as the catalog instead of SQLite:

```sql
ATTACH 'ducklake:postgresql://user:pass@localhost/ducklake' AS safecast
    (DATA_PATH '/var/lib/grafana/data/ducklake_data/');
```

**Pros:**
- PostgreSQL supports PRIMARY KEY constraints
- Better for high-concurrency scenarios
- More scalable

**Cons:**
- Requires PostgreSQL server setup
- More complex infrastructure
- Overkill for your current needs (2 concurrent connections)

For your use case (Grafana + one script), SQLite catalog with application-level deduplication is the right choice.

---

## Current Status: Working Solution ✅

The scripts have been updated to work without PRIMARY KEY constraints. The deduplication logic works correctly and maintains data integrity while enabling concurrent access.

**Bottom line:** This limitation doesn't prevent DuckLake from solving your concurrent access problem!
