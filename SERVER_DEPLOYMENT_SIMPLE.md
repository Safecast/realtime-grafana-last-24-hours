# Server Deployment Guide - Simple Flip-Flop Approach

Complete guide for deploying the simple flip-flop database architecture to **grafana.safecast.jp**.

## Overview

This guide will set up the same system that's working locally:
- **Script:** `update-flipflop-simple.sh`
- **Architecture:** Flip-flop (A/B databases + symlink)
- **Updates:** Every 5 minutes via cron
- **Downtime:** ~30-60 seconds per update (acceptable)
- **No DuckLake:** Direct TTServer → DuckDB flow

---

## Prerequisites

Before starting, ensure you have:
- SSH access to `grafana.safecast.jp`
- Root or sudo privileges
- Git repository cloned on server
- DuckDB installed on server
- Grafana with MotherDuck plugin

---

## Step 1: Connect to Server

```bash
ssh root@grafana.safecast.jp
cd /home/grafana.safecast.jp/public_html
```

---

## Step 2: Pull Latest Code

```bash
# Make sure repo is clean
git status

# Pull latest changes with flip-flop script
git pull origin main

# Verify the simple flip-flop script exists
ls -l update-flipflop-simple.sh
chmod +x update-flipflop-simple.sh
```

---

## Step 3: Verify DuckDB Installation

```bash
# Check DuckDB version
duckdb --version

# If not installed, install it:
wget https://github.com/duckdb/duckdb/releases/download/v1.4.1/duckdb_cli-linux-amd64.zip
unzip duckdb_cli-linux-amd64.zip
mkdir -p ~/.local/bin
mv duckdb ~/.local/bin/
chmod +x ~/.local/bin/duckdb

# Add to PATH if needed
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

---

## Step 4: Verify Required Tools

```bash
# Check for required tools
which jq      # JSON processor
which wget    # API fetcher

# Install if missing (Ubuntu/Debian)
apt-get update
apt-get install -y jq wget
```

---

## Step 5: Set Up Passwordless Sudo for Grafana

The flip-flop script needs to stop/start Grafana without password prompts:

```bash
# Create sudoers file for Grafana management
sudo bash -c 'cat > /etc/sudoers.d/grafana-restart << EOF
root ALL=(ALL) NOPASSWD: /bin/systemctl stop grafana-server
root ALL=(ALL) NOPASSWD: /bin/systemctl start grafana-server
root ALL=(ALL) NOPASSWD: /bin/systemctl restart grafana-server
root ALL=(ALL) NOPASSWD: /bin/systemctl status grafana-server
root ALL=(ALL) NOPASSWD: /usr/bin/chown grafana:grafana /var/lib/grafana/data/*
root ALL=(ALL) NOPASSWD: /usr/bin/chmod 664 /var/lib/grafana/data/*.duckdb
EOF'

# Set correct permissions
sudo chmod 440 /etc/sudoers.d/grafana-restart

# Verify it works
sudo systemctl status grafana-server
```

---

## Step 6: Back Up Existing Database

**IMPORTANT:** Back up your current database before switching to flip-flop!

```bash
# Check current database location
ls -lh /var/lib/grafana/data/*.duckdb

# Back it up
sudo cp /var/lib/grafana/data/devices.duckdb /var/lib/grafana/data/devices.duckdb.backup.$(date +%Y%m%d)

# Verify backup size
ls -lh /var/lib/grafana/data/*.backup.*
```

---

## Step 7: Set Up Flip-Flop Databases

```bash
# Stop Grafana first
sudo systemctl stop grafana-server

# Copy current database to both A and B
sudo cp /var/lib/grafana/data/devices.duckdb /var/lib/grafana/data/devices_a.duckdb
sudo cp /var/lib/grafana/data/devices.duckdb /var/lib/grafana/data/devices_b.duckdb

# Create symlink pointing to A
sudo rm -f /var/lib/grafana/data/devices.duckdb
sudo ln -s devices_a.duckdb /var/lib/grafana/data/devices.duckdb

# Create state file tracking active database
echo "A" | sudo tee /var/lib/grafana/data/.active_db

# Set permissions
sudo chown grafana:grafana /var/lib/grafana/data/devices*.duckdb
sudo chown grafana:grafana /var/lib/grafana/data/.active_db
sudo chmod 664 /var/lib/grafana/data/devices*.duckdb
sudo chmod 664 /var/lib/grafana/data/.active_db

# Verify setup
ls -la /var/lib/grafana/data/devices*.duckdb
cat /var/lib/grafana/data/.active_db
```

---

## Step 8: Test the Script

Run the flip-flop script manually to verify it works:

```bash
cd /home/grafana.safecast.jp/public_html
./update-flipflop-simple.sh
```

**Expected output:**
```
==========================================
Simple flip-flop update starting...
==========================================
Active DB: A (Grafana reads from this)
Target DB: B (Writing new data here)
Stopping Grafana to unlock databases...
Fetching data from TTServer and writing to /var/lib/grafana/data/devices_b.duckdb...
Fetching device data from TTServer...
Fetched 1456 device records
[DuckDB operations...]
Switching active database to B...
Restarting Grafana...
==========================================
✅ Simple flip-flop update complete!
Active DB: B (/var/lib/grafana/data/devices_b.duckdb)
Grafana is back online!
==========================================
```

**Verify:**
```bash
# Check Grafana is running
sudo systemctl status grafana-server

# Check which DB is active
cat /var/lib/grafana/data/.active_db
ls -la /var/lib/grafana/data/devices.duckdb

# Check data was inserted
duckdb /var/lib/grafana/data/devices.duckdb "SELECT COUNT(*) FROM measurements;"
```

---

## Step 9: Configure Grafana Data Source

1. **Open Grafana**: https://grafana.safecast.jp

2. **Go to Configuration → Data Sources**

3. **Edit or Add MotherDuck Data Source**:
   - **Name:** `Safecast Devices`
   - **Connection Type:** Local DuckDB File
   - **Database Path:** `/var/lib/grafana/data/devices.duckdb` ⚠️ Use symlink, NOT _a or _b!
   - **Save & Test**

4. **Verify Connection:**
   ```sql
   SELECT COUNT(*) as total FROM measurements
   ```

---

## Step 10: Set Up Cron Job

```bash
# Edit crontab
crontab -e

# Add this line (run every 5 minutes):
*/5 * * * * cd /home/grafana.safecast.jp/public_html && ./update-flipflop-simple.sh >> /home/grafana.safecast.jp/public_html/flipflop.log 2>&1

# Save and exit

# Verify cron job is installed
crontab -l
```

---

## Step 11: Monitor the System

### Watch the Log

```bash
tail -f /home/grafana.safecast.jp/public_html/flipflop.log
```

### Check Database Sizes

```bash
ls -lh /var/lib/grafana/data/devices*.duckdb
```

### Check Which Database is Active

```bash
cat /var/lib/grafana/data/.active_db
ls -la /var/lib/grafana/data/devices.duckdb
```

### Verify Data is Fresh

```bash
duckdb /var/lib/grafana/data/devices.duckdb "
SELECT
    MAX(when_captured) as latest_reading,
    COUNT(*) as total_measurements
FROM measurements;
"
```

---

## Troubleshooting

### Cron Job Not Running

```bash
# Check cron service
sudo systemctl status cron

# Check for errors in syslog
grep CRON /var/log/syslog | tail -20

# Test script manually
cd /home/grafana.safecast.jp/public_html
./update-flipflop-simple.sh
```

### Database Locking Errors

If you see "Conflicting lock" errors:

1. **Check Grafana data source** points to symlink:
   - ✅ Correct: `/var/lib/grafana/data/devices.duckdb`
   - ❌ Wrong: `/var/lib/grafana/data/devices_a.duckdb`

2. **Verify passwordless sudo works:**
   ```bash
   sudo systemctl stop grafana-server
   sudo systemctl start grafana-server
   ```

### Grafana Shows Old Data

```bash
# Check symlink
ls -la /var/lib/grafana/data/devices.duckdb

# Check active database
cat /var/lib/grafana/data/.active_db

# Force manual update
./update-flipflop-simple.sh

# Restart Grafana
sudo systemctl restart grafana-server
```

### Script Fails with "wget not found"

```bash
apt-get install -y wget
```

### Script Fails with "jq not found"

```bash
apt-get install -y jq
```

---

## Performance Tuning

### Query Optimization

Use the pre-aggregated summary tables in Grafana queries:

**Fast hourly data:**
```sql
SELECT
    hour as time,
    device_sn,
    avg_radiation,
    avg_temp
FROM hourly_summary
WHERE hour >= NOW() - INTERVAL 24 HOURS
ORDER BY hour
```

**Recent detailed data:**
```sql
SELECT
    when_captured as time,
    device_urn,
    lnd_7318u as radiation
FROM recent_data
WHERE when_captured >= NOW() - INTERVAL 24 HOURS
```

### Database Maintenance

```bash
# Check database size
du -h /var/lib/grafana/data/devices*.duckdb

# View table sizes
duckdb /var/lib/grafana/data/devices.duckdb "
SELECT
    table_name,
    estimated_size
FROM duckdb_tables();
"

# Verify indexes exist
duckdb /var/lib/grafana/data/devices.duckdb "
PRAGMA show_tables;
"
```

---

## Rollback Plan

If something goes wrong, you can rollback:

```bash
# Stop Grafana
sudo systemctl stop grafana-server

# Restore from backup
sudo cp /var/lib/grafana/data/devices.duckdb.backup.YYYYMMDD /var/lib/grafana/data/devices.duckdb

# Remove flip-flop files
sudo rm /var/lib/grafana/data/devices_a.duckdb
sudo rm /var/lib/grafana/data/devices_b.duckdb
sudo rm /var/lib/grafana/data/.active_db

# Set permissions
sudo chown grafana:grafana /var/lib/grafana/data/devices.duckdb
sudo chmod 664 /var/lib/grafana/data/devices.duckdb

# Start Grafana
sudo systemctl start grafana-server

# Remove cron job
crontab -e
# (delete the flip-flop line)
```

---

## Verification Checklist

- [ ] DuckDB installed and in PATH
- [ ] `update-flipflop-simple.sh` executable
- [ ] Passwordless sudo configured
- [ ] Backup of original database created
- [ ] Flip-flop databases (A and B) created
- [ ] Symlink points to one of the databases
- [ ] State file exists and contains "A" or "B"
- [ ] Manual test run successful
- [ ] Grafana data source points to symlink
- [ ] Cron job installed and running
- [ ] Log file shows successful updates
- [ ] Grafana shows current data

---

## Support

If you encounter issues:

1. Check the log: `tail -f /home/grafana.safecast.jp/public_html/flipflop.log`
2. Review troubleshooting section above
3. Check GitHub issues: https://github.com/Safecast/realtime-grafana-last-24-hours/issues
4. Test locally first to validate the approach

---

## What's Different from Local Setup?

| Aspect | Local | Server |
|--------|-------|--------|
| **Path** | `/home/rob/Documents/realtime-grafana-last-24-hours` | `/home/grafana.safecast.jp/public_html` |
| **User** | `rob` | `root` or server user |
| **Database** | `/var/lib/grafana/data/` | Same |
| **Log** | `flipflop.log` | `flipflop.log` |
| **Cron** | User crontab | User/root crontab |
| **Everything else** | Identical! | Identical! |

The script is portable and works the same way on both environments!
