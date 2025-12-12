# realtime-grafana-last-24-hours

## Quick start
### Notes
**Safecast Devices (PostgreSQL)**
- **Script:** `devices-last-24-hours.sh` (root of repo)
- **DB connection:** set environment variables `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD` (or set `PG_CONN` with a libpq connection string).
- **Example (local test):**
```
export PGHOST=localhost
export PGPORT=5432
export PGDATABASE=safecast
export PGUSER=safecast
export PGPASSWORD='change_me_in_production'
bash devices-last-24-hours.sh
```
- **Behavior:** Uses `/dev/shm` for a temporary CSV, stages into a temp table, then inserts new rows into `measurements`. Deduplication is performed using `(device_urn, when_captured)`. The script does not alter the DB schema.
- **Logging:** All stdout/stderr is redirected to `script.log` with timestamps.
- **Service:** Recommended to run via a systemd `oneshot` service + `timer` (see developer notes in repository). Ensure the DB role has `INSERT` privileges on `measurements`.

# Real-time Grafana Setup for the Last 24 Hours

## Table of Contents

1. [Overview](#overview)
2. [Features](#features)
3. [Prerequisites](#prerequisites)
4. [Installation](#installation)
5. [Usage](#usage)
6. [Configuration](#configuration)
7. [Data Processing Workflow](#data-processing-workflow)
8. [Grafana Setup](#grafana-setup)
9. [Troubleshooting](#troubleshooting)
10. [License](#license)

---

### Overview

This project provides a real-time Grafana dashboard for Safecast device monitoring, pulling data from TTServer every 5 minutes and storing it in DuckDB. It uses a **flip-flop database approach** to eliminate locking issues and ensure continuous Grafana availability.

### Features

- **Flip-Flop Database Architecture**: Uses two databases (A/B) with atomic symlink switching for zero-conflict updates
- **Automated Data Collection**: Fetches device data every 5 minutes from TTServer
- **Performance Optimized**: Pre-aggregated summary tables for 18-20x faster Grafana queries
- **No Locking Issues**: Grafana reads from active DB while updates write to inactive DB
- **Simple, Maintainable**: Direct TTServer → DuckDB flow without complex dependencies
- **DuckDB Integration**: Efficient columnar storage for time-series data

### Prerequisites

- **Linux Environment**: Ubuntu/Debian recommended
- **DuckDB**: Database engine for time-series data storage
- **Grafana**: Visualization platform with MotherDuck DuckDB data source plugin
- **jq**: JSON processing tool
- **wget**: For API data fetching
- **Passwordless sudo**: For Grafana service management (see setup below)

### Installation

1. **Clone the Repository**:

   ```bash
   git clone https://github.com/Safecast/realtime-grafana-last-24-hours.git
   cd realtime-grafana-last-24-hours
   ```

2. **Install DuckDB**:

   ```bash
   wget https://github.com/duckdb/duckdb/releases/download/v1.4.1/duckdb_cli-linux-amd64.zip
   unzip duckdb_cli-linux-amd64.zip
   mkdir -p ~/.local/bin
   mv duckdb ~/.local/bin/
   chmod +x ~/.local/bin/duckdb
   ```

3. **Install Grafana and MotherDuck Plugin**:

   ```bash
   # Install Grafana (Ubuntu/Debian)
   sudo apt-get install -y software-properties-common
   sudo add-apt-repository "deb https://packages.grafana.com/oss/deb stable main"
   wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
   sudo apt-get update
   sudo apt-get install grafana

   # Install MotherDuck DuckDB plugin
   sudo grafana-cli plugins install motherduck-motherduck-datasource
   sudo systemctl restart grafana-server
   ```

4. **Set Up Passwordless Sudo for Grafana Restarts**:

   ```bash
   sudo bash -c 'cat > /etc/sudoers.d/grafana-restart << EOF
   rob ALL=(ALL) NOPASSWD: /bin/systemctl stop grafana-server
   rob ALL=(ALL) NOPASSWD: /bin/systemctl start grafana-server
   rob ALL=(ALL) NOPASSWD: /bin/systemctl restart grafana-server
   EOF'
   sudo chmod 440 /etc/sudoers.d/grafana-restart
   ```

### Usage

#### Manual Update

Run the flip-flop update manually:

```bash
./update-flipflop-simple.sh
```

#### Automated Updates (Cron)

Set up automated updates every 5 minutes:

1. Edit the crontab:

   ```bash
   crontab -e
   ```

2. Add this entry:

   ```bash
   */5 * * * * cd /home/rob/Documents/realtime-grafana-last-24-hours && ./update-flipflop-simple.sh >> /home/rob/Documents/realtime-grafana-last-24-hours/flipflop.log 2>&1
   ```

3. Monitor the log:

   ```bash
   tail -f /home/rob/Documents/realtime-grafana-last-24-hours/flipflop.log
   ```

### How It Works: Flip-Flop Architecture

The flip-flop approach eliminates database locking issues:

```
┌─────────────────┐      ┌──────────────────────┐
│   TTServer API  │      │   Two Databases      │
│                 │      │                      │
│  Device Data    │──────▶   devices_a.duckdb  │
│  (JSON)         │      │   devices_b.duckdb  │
└─────────────────┘      └──────────────────────┘
                                    │
                                    ▼
                         ┌──────────────────────┐
                         │  Symlink (atomic)    │
                         │  devices.duckdb ────▶│
                         └──────────────────────┘
                                    │
                                    ▼
                         ┌──────────────────────┐
                         │     Grafana          │
                         │  (reads via symlink) │
                         └──────────────────────┘
```

**Update Flow:**

1. **Determine Active DB**: Check which database (A or B) Grafana is currently reading
2. **Stop Grafana**: Brief pause to release locks (~5 seconds)
3. **Write to Inactive DB**: Fetch TTServer data and write to the inactive database
4. **Update Summary Tables**: Refresh hourly_summary, recent_data, daily_summary
5. **Atomic Flip**: Change symlink to point to newly updated database
6. **Restart Grafana**: Back online (~10 seconds)

**Total downtime: ~30-60 seconds** (acceptable for 5-minute update intervals)

### Data Processing Workflow

1. **Fetch Data**: Pull device readings from TTServer API (`https://tt.safecast.org/devices`)
2. **Validate & Filter**: Remove invalid timestamps, filter to last 30 days
3. **Store Measurements**: Insert into inactive database (no conflicts!)
4. **Create Summaries**: Generate pre-aggregated tables for fast queries:
   - `hourly_summary`: Hourly averages for last 30 days
   - `recent_data`: All readings from last 7 days
   - `daily_summary`: Daily aggregates for all data
5. **Flip Database**: Atomic symlink switch makes new data visible to Grafana

### Grafana Setup

1. **Configure MotherDuck Data Source**:
   - Open Grafana (http://localhost:3000)
   - Go to Configuration → Data Sources
   - Add MotherDuck data source
   - Set database path: `/var/lib/grafana/data/devices.duckdb` (the symlink!)
   - Save & Test

2. **Create Dashboard Queries**:

   **Fast query using summary table:**
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

   **Recent data (last 7 days):**
   ```sql
   SELECT
       when_captured as time,
       device_urn,
       lnd_7318u as radiation
   FROM recent_data
   WHERE when_captured >= NOW() - INTERVAL 24 HOURS
   ORDER BY when_captured DESC
   ```

### Performance

- **Query Speed**: 18-20x faster with summary tables (590ms → 30-50ms)
- **Database Size**: ~1.6GB for 238K measurements (30 days)
- **Update Time**: ~30-60 seconds every 5 minutes
- **Summary Tables**: Pre-aggregated hourly/daily data eliminates expensive GROUP BY queries
- **Dashboards**: Use the pre-configured dashboards located in the Dashboards folder to visualize data.

### Troubleshooting

#### Data Not Updating

```bash
# Check cron job status
tail -f /home/rob/Documents/realtime-grafana-last-24-hours/flipflop.log

# Run manual update to see errors
./update-flipflop-simple.sh
```

#### Database Locking Errors

If you see "Conflicting lock" errors:
- Make sure Grafana is configured to read from `/var/lib/grafana/data/devices.duckdb` (symlink)
- NOT from `devices_a.duckdb` or `devices_b.duckdb` directly
- The script stops Grafana automatically, but check it's actually stopping:
  ```bash
  sudo systemctl status grafana-server
  ```

#### Grafana Not Displaying Data

1. Check data source configuration points to symlink
2. Verify permissions:
   ```bash
   sudo chown grafana:grafana /var/lib/grafana/data/devices*.duckdb
   sudo chmod 664 /var/lib/grafana/data/devices*.duckdb
   ```
3. Check which database is active:
   ```bash
   ls -la /var/lib/grafana/data/devices.duckdb
   cat /var/lib/grafana/data/.active_db
   ```

#### Invalid Timestamp Errors

The script handles invalid timestamps (like `2012-00-00T00:00:00Z`) automatically using `TRY_CAST`. If you see these errors, the script continues and filters them out.

#### Performance Issues

If queries are slow:
- Use summary tables (`hourly_summary`, `recent_data`, `daily_summary`)
- Check indexes exist:
  ```bash
  duckdb /var/lib/grafana/data/devices.duckdb "SHOW TABLES; PRAGMA show_tables;"
  ```

### License

This project is licensed under the MIT License. See the LICENSE file for more details.

---

![image(1)](https://github.com/user-attachments/assets/4511bf04-8604-45d6-b5fc-0e79461cf0ab)
![image(2)](https://github.com/user-attachments/assets/03580588-5e55-46e0-84c0-e3b43a09542e)
![image(3)](https://github.com/user-attachments/assets/6095637b-c3a4-40be-a1cd-f331990b159f)
![image(4)](https://github.com/user-attachments/assets/7ec751bd-898d-42bd-9079-e8fc96033aa5)
