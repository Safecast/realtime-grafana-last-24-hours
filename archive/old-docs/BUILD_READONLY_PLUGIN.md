# Building Read-Only MotherDuck DuckDB Plugin for Grafana

## The Problem

The MotherDuck DuckDB Grafana plugin opens the database with a WRITE lock, preventing concurrent access. This causes the data collection script to fail when Grafana is viewing dashboards.

## The Solution

Modify the plugin source code to open the database in `READ_ONLY` mode, allowing:
- ✅ Grafana to read data without blocking
- ✅ Data collection script to write while Grafana is active
- ✅ True concurrent access via DuckDB's WAL mode

---

## Prerequisites

Install these on your LOCAL machine (not the server):

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y golang-1.21 build-essential git nodejs npm

# Verify installations
go version    # Should be 1.21+
gcc --version
node --version
npm --version
```

---

## Build Steps

### 1. Run the build script

```bash
cd ~/Documents/realtime-grafana-last-24-hours
./build-readonly-plugin.sh
```

The script will:
1. Clone the MotherDuck DuckDB datasource repository
2. Apply the READ_ONLY patch
3. Build the backend (Go)
4. Build the frontend (Node.js)
5. Create a distribution package in `/tmp/grafana-duckdb-build/`

**Build time:** ~5-10 minutes depending on your system

---

## Installation on Server

After building successfully, install the modified plugin on your server:

### Step 1: Stop Grafana

```bash
ssh root@grafana.safecast.jp
sudo systemctl stop grafana-server
```

### Step 2: Backup existing plugin

```bash
sudo mv /var/lib/grafana/plugins/motherduck-duckdb-datasource \
        /var/lib/grafana/plugins/motherduck-duckdb-datasource.backup
```

### Step 3: Copy new plugin to server

From your LOCAL machine:

```bash
scp -r /tmp/grafana-duckdb-build/motherduck-duckdb-datasource-readonly \
       root@grafana.safecast.jp:/var/lib/grafana/plugins/motherduck-duckdb-datasource
```

### Step 4: Set permissions

On the server:

```bash
ssh root@grafana.safecast.jp
sudo chown -R grafana:grafana /var/lib/grafana/plugins/motherduck-duckdb-datasource
sudo chmod -R 755 /var/lib/grafana/plugins/motherduck-duckdb-datasource
```

### Step 5: Start Grafana

```bash
sudo systemctl start grafana-server
sudo systemctl status grafana-server
```

---

## Verify It Works

### Test 1: Check Grafana logs for READ_ONLY message

```bash
sudo journalctl -u grafana-server -f | grep READ_ONLY
```

You should see:
```
Opening DuckDB in READ_ONLY mode path=/var/lib/grafana/data/devices.duckdb?access_mode=READ_ONLY
```

### Test 2: Check file lock type

```bash
lsof /var/lib/grafana/data/devices.duckdb
```

Should show:
```
COMMAND      PID    USER   FD   TYPE DEVICE SIZE/OFF    NODE NAME
gpx_duckd 597726 grafana   11uR  REG    8,2  4730880 1445713 /var/lib/grafana/data/devices.duckdb
                               ^^--- READ lock (not WRITE)
```

The `R` flag means READ-ONLY, not `W` for WRITE.

### Test 3: Run data collection with Grafana dashboard open

Open your Grafana dashboard in a browser, then:

```bash
./devices-last-24-hours.sh
```

Should complete successfully without locking errors!

---

## Troubleshooting

### Build fails with "go: command not found"

Install Go 1.21+:
```bash
wget https://go.dev/dl/go1.21.6.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.21.6.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin
```

### Build fails with "gcc: command not found"

Install build tools:
```bash
sudo apt-get install build-essential
```

### Plugin doesn't load in Grafana

Check Grafana logs:
```bash
sudo journalctl -u grafana-server -n 100 --no-pager
```

Look for unsigned plugin errors. The plugin should still be allowed since we already configured:
```ini
allow_loading_unsigned_plugins = motherduck-duckdb-datasource
```

### Still getting locking errors

1. Verify the patch was applied:
```bash
grep "READ_ONLY" /var/lib/grafana/plugins/motherduck-duckdb-datasource/gpx_duckdb_datasource_linux_amd64
```

2. Restart Grafana completely:
```bash
sudo systemctl restart grafana-server
```

3. Check if WAL mode is enabled in the database:
```bash
/root/.local/bin/duckdb /var/lib/grafana/data/devices.duckdb \
  -c "PRAGMA database_list;"
```

---

## Rollback (if needed)

If something goes wrong, restore the original plugin:

```bash
sudo systemctl stop grafana-server
sudo rm -rf /var/lib/grafana/plugins/motherduck-duckdb-datasource
sudo mv /var/lib/grafana/plugins/motherduck-duckdb-datasource.backup \
        /var/lib/grafana/plugins/motherduck-duckdb-datasource
sudo systemctl start grafana-server
```

---

## What the Patch Does

The patch modifies `pkg/plugin/duckdb_driver.go` to append `?access_mode=READ_ONLY` to the database path for local files:

```go
// Before:
connector, err := duckdb.NewConnector(path, func(execer driver.ExecerContext) error {

// After:
if path != "" && !strings.HasPrefix(config.Path, "md:") {
    path = path + "?access_mode=READ_ONLY"
    backend.Logger.Info("Opening DuckDB in READ_ONLY mode", "path", path)
}
connector, err := duckdb.NewConnector(path, func(execer driver.ExecerContext) error {
```

This forces Grafana to open the database with a READ lock instead of WRITE lock, enabling true concurrent access.

---

## Success Indicators

✅ Grafana dashboards display data correctly
✅ `lsof` shows READ lock (`11uR`) not WRITE lock (`11uW`)
✅ Data collection script runs successfully while Grafana dashboard is open
✅ No more "Conflicting lock" errors
✅ `.wal` file appears during concurrent access

