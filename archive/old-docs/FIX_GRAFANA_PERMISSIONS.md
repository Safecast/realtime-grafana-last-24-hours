# Fix Grafana Permission Error

## The Problem

When configuring the DuckDB data source in Grafana, you're getting this error:

```
database/sql/driver: could not connect to database: duckdb error:
IO Error: Cannot open file "/home/rob/Documents/realtime-grafana-last-24-hours/devices.duckdb":
Permission denied
```

**Root cause**: The Grafana server runs as user `grafana`, which cannot access files in `/home/rob/` because the home directory has restricted permissions.

---

## ✅ Solution 1: Move Database to Shared Location (RECOMMENDED)

This is the cleanest and most secure solution.

### Step 1: Run the Setup Script

```bash
cd /home/rob/Documents/realtime-grafana-last-24-hours
./setup-shared-database.sh
```

This script will:
- ✅ Create `/var/lib/grafana/data/` directory
- ✅ Copy your existing database to the new location
- ✅ Add user `rob` to the `grafana` group
- ✅ Set proper permissions

### Step 2: Log Out and Back In

**IMPORTANT**: For the group changes to take effect, you must log out and log back in!

```bash
# Log out and log back in, then verify you're in the grafana group:
groups
# Should show: rob ... grafana
```

### Step 3: Update Grafana Data Source

In Grafana, configure the DuckDB data source with this path:
```
/var/lib/grafana/data/devices.duckdb
```

### Step 4: Test

Run the data collection script to verify it works:
```bash
./devices-last-24-hours.sh
```

**Done!** ✅ The database is now in a shared location accessible by both rob and grafana.

---

## 🔧 Solution 2: Give Grafana User Access to /home/rob (NOT RECOMMENDED)

This is less secure but simpler if you don't want to move the database.

```bash
# Add grafana user to rob's group
sudo usermod -a -G rob grafana

# Give group read access to /home/rob
chmod g+r /home/rob

# Restart Grafana
sudo systemctl restart grafana-server
```

Then in Grafana, use:
```
/home/rob/Documents/realtime-grafana-last-24-hours/devices.duckdb
```

**Warning**: This gives the grafana user access to your entire home directory.

---

## 🔧 Solution 3: Create a Symbolic Link

If you want to keep the database in your home directory but make it accessible:

```bash
# Create a shared directory
sudo mkdir -p /opt/safecast
sudo chown rob:grafana /opt/safecast
sudo chmod 775 /opt/safecast

# Create a symbolic link
ln -s /home/rob/Documents/realtime-grafana-last-24-hours/devices.duckdb /opt/safecast/devices.duckdb

# Update the database path in the script
# Edit devices-last-24-hours.sh and change:
#   DB_PATH="/opt/safecast/devices.duckdb"
```

**Note**: This doesn't solve the permission issue - grafana still can't read through the symlink because it can't access /home/rob.

---

## Verify Permissions

After applying any solution, verify the permissions:

```bash
# Check the database file
ls -la /var/lib/grafana/data/devices.duckdb

# Should show:
# -rw-rw-r-- 1 grafana grafana ... devices.duckdb

# Check directory permissions
namei -l /var/lib/grafana/data/devices.duckdb

# All directories should be readable by grafana
```

---

## Test Connection in Grafana

1. Go to: **Configuration → Data Sources → DuckDB**
2. Path: `/var/lib/grafana/data/devices.duckdb`
3. Click **"Save & Test"**

Should show: ✅ **"Data source is working"**

---

## Troubleshooting

### Still getting permission errors?

Check the grafana user can read the file:
```bash
sudo -u grafana ls -la /var/lib/grafana/data/devices.duckdb
```

If that fails, check permissions:
```bash
sudo chmod 664 /var/lib/grafana/data/devices.duckdb
sudo chown grafana:grafana /var/lib/grafana/data/devices.duckdb
```

### Database file not updating?

Make sure rob is in the grafana group:
```bash
groups
# Should include "grafana"
```

If not, log out and log back in after running the setup script.

### Grafana shows "Database locked"?

Stop any processes using the database:
```bash
# Check if duckdb processes are running
ps aux | grep duckdb

# Make sure the data collection script isn't running
ps aux | grep devices-last-24-hours
```

---

## Updated File Paths

After using Solution 1, your setup will be:

| Item | Path |
|------|------|
| **Database file** | `/var/lib/grafana/data/devices.duckdb` |
| **Data collection script** | `/home/rob/Documents/realtime-grafana-last-24-hours/devices-last-24-hours.sh` |
| **Grafana config** | Path: `/var/lib/grafana/data/devices.duckdb` |

---

## Automated Setup (Recommended Path)

```bash
# 1. Run setup script
cd /home/rob/Documents/realtime-grafana-last-24-hours
./setup-shared-database.sh

# 2. Log out and back in
exit
# (log back in)

# 3. Test the data collection
./devices-last-24-hours.sh

# 4. Configure Grafana
#    Path: /var/lib/grafana/data/devices.duckdb

# Done! ✅
```

---

## Cron Job Update

If you have a cron job, it will work automatically with the new database location since the script has been updated to use `/var/lib/grafana/data/devices.duckdb`.

Your cron entry (no changes needed):
```bash
*/15 * * * * cd /home/rob/Documents/realtime-grafana-last-24-hours && ./devices-last-24-hours.sh
```

---

## Summary

**Best solution**: Run `./setup-shared-database.sh` → Log out/in → Update Grafana path to `/var/lib/grafana/data/devices.duckdb`

This gives you:
- ✅ Secure permissions
- ✅ Both rob and grafana can access the database
- ✅ No security issues with exposing /home/rob
- ✅ Standard Linux file location for shared data
