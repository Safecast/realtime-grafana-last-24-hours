# DuckLake Approach Archive

This folder contains scripts for the DuckLake-based flip-flop approaches that are **no longer recommended** for this project.

## Why Archived?

The DuckLake approach added complexity without solving the core locking issue:
- Grafana's DuckDB plugin locks all `.duckdb` files in a directory
- This defeats the flip-flop zero-downtime goal
- Both approaches (simple and DuckLake) require stopping Grafana anyway
- The simple approach is easier to maintain

## Archived Scripts

### DuckLake Migration
- `migrate-to-ducklake.sh` - Generic DuckLake migration
- `migrate-to-ducklake-local.sh` - Local environment migration
- `migrate-to-ducklake-server.sh` - Server environment migration

### DuckLake Data Collection
- `devices-last-24-hours-ducklake.sh` - Fetch data and write to DuckLake

### Flip-Flop with DuckLake
- `update-flipflop.sh` - Full copy flip-flop using DuckLake
- `update-flipflop-incremental.sh` - Incremental sync flip-flop using DuckLake

### Helper Scripts
- `export-ducklake-to-duckdb.sh` - Export DuckLake to standard DuckDB
- `create-grafana-view.sh` - View creation helper
- `sync-incremental.sh` - Incremental sync helper
- `update-and-sync.sh` - Combined update wrapper

## Current Recommended Approach

Use **`update-flipflop-simple.sh`** in the root directory:
- Direct TTServer → DuckDB flow
- No DuckLake dependency
- Simpler, more maintainable
- Same performance

## Cleanup (Optional)

If you want to fully remove DuckLake:

```bash
# Remove DuckLake database files (optional - only if not needed)
sudo rm -rf /var/lib/grafana/data/ducklake_catalog.db*
sudo rm -rf /var/lib/grafana/data/ducklake_data/

# The flip-flop databases (devices_a.duckdb, devices_b.duckdb) are still used
# by update-flipflop-simple.sh, so keep those!
```

## If You Need These Scripts

These scripts are preserved in git history and can be restored if needed:
```bash
git log --all --full-history -- "archive/ducklake-approach/*"
```
