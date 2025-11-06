# Suggested Comment for GitHub Issue #51

## Technical Implementation Suggestion

I've investigated how to implement read-only mode and have a working solution. Here's what needs to be changed:

### Root Cause
The plugin currently opens DuckDB with a WRITE lock by default in [`pkg/plugin/duckdb_driver.go`](https://github.com/motherduckdb/grafana-duckdb-datasource/blob/main/pkg/plugin/duckdb_driver.go). This prevents concurrent access when another process needs to write to the database.

Verified with `lsof`:
```bash
lsof /var/lib/grafana/data/devices.duckdb
# Shows: 11uW (WRITE lock) instead of 11uR (READ lock)
```

### Proposed Solution

Add a configuration option in the datasource settings to enable read-only mode:

**1. Frontend Changes** (`src/components/ConfigEditor.tsx`):
```typescript
<InlineField label="Read Only Mode" labelWidth={26}>
  <InlineSwitch
    value={options.jsonData.readOnly || false}
    onChange={(event) =>
      onOptionsChange({
        ...options,
        jsonData: {
          ...options.jsonData,
          readOnly: event!.currentTarget.checked,
        },
      })
    }
  />
</InlineField>
```

**2. Backend Changes** (`pkg/plugin/duckdb_driver.go`, around line 78):
```go
// After setting the path variable:
if path != "" && !strings.HasPrefix(cleanPath, "md:") {
    // Check if read-only mode is enabled in config
    if config.ReadOnly {
        path = path + "?access_mode=READ_ONLY"
        backend.Logger.Info("Opening DuckDB in READ_ONLY mode", "path", path)
    }
}
```

**3. Model Changes** (`pkg/models/settings.go`):
```go
type PluginSettings struct {
    Path     string `json:"path"`
    ReadOnly bool   `json:"readOnly"`
    Secrets  SecureSettings
}
```

### Benefits
- ✅ Allows concurrent read (Grafana) + write (data collection scripts) access
- ✅ Prevents accidental database modifications through Grafana
- ✅ Leverages DuckDB's built-in `access_mode=READ_ONLY` parameter
- ✅ Optional feature - doesn't break existing setups

### Use Case
I'm running a data collection script that writes to DuckDB every 15 minutes while Grafana dashboards need to read the data continuously. Currently, the plugin holds a WRITE lock, causing "Conflicting lock" errors when the script tries to insert data.

With read-only mode, Grafana would only acquire a READ lock, allowing my script to write concurrently via DuckDB's WAL mode.

### Workaround (Until Feature Is Implemented)
For others with this issue, I'm using retry logic in my data collection script:
- Retry up to 10 times with 3-second delays
- Catches brief moments when Grafana releases the lock between queries
- Works adequately for automated collection, but not ideal

Would appreciate if the maintainers could implement this feature!
