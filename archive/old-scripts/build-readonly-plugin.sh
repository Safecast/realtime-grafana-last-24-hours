#!/bin/bash

# -----------------------------------------------------------------------------
# Script: build-readonly-plugin.sh
# Description: Builds MotherDuck DuckDB plugin with READ_ONLY mode for Grafana
# -----------------------------------------------------------------------------

set -e

echo "=========================================="
echo "Building Read-Only DuckDB Grafana Plugin"
echo "=========================================="
echo ""

# Check prerequisites
echo "Checking prerequisites..."
if ! command -v go &> /dev/null; then
    echo "❌ Error: Go is not installed. Install Go 1.21+ first."
    exit 1
fi

if ! command -v git &> /dev/null; then
    echo "❌ Error: git is not installed."
    exit 1
fi

if ! command -v gcc &> /dev/null; then
    echo "❌ Error: gcc is not installed. Install build-essential."
    exit 1
fi

echo "✅ Prerequisites checked"
echo ""

# Create working directory
WORK_DIR="/tmp/grafana-duckdb-build"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Clone repository
echo "📥 Cloning MotherDuck DuckDB datasource repository..."
git clone https://github.com/motherduckdb/grafana-duckdb-datasource.git
cd grafana-duckdb-datasource

# Apply modification directly using sed
echo ""
echo "🔧 Applying READ_ONLY mode modification..."

# Find the line with "// connect with the path" and insert our code before it
sed -i '/^[[:space:]]*\/\/ connect with the path before any other queries are run\./i\
\
\t// Force read-only mode for local database files to allow concurrent access\
\t// Only apply to non-MotherDuck local files\
\tif path != "" && !strings.HasPrefix(cleanPath, "md:") {\
\t\tpath = path + "?access_mode=READ_ONLY"\
\t\tbackend.Logger.Info("Opening DuckDB in READ_ONLY mode", "path", path)\
\t}\
' pkg/plugin/duckdb_driver.go

# Verify the modification was applied
if grep -q "access_mode=READ_ONLY" pkg/plugin/duckdb_driver.go; then
    echo "✅ Modification applied successfully"
else
    echo "❌ Error: Failed to apply modification"
    exit 1
fi

# Build backend
echo ""
echo "🔨 Building plugin backend..."
go build -o gpx_duckdb_datasource_linux_amd64 ./pkg

# Build frontend
echo ""
echo "📦 Building plugin frontend..."
npm install
npm run build

# Create distribution directory
echo ""
echo "📂 Creating distribution package..."
DIST_DIR="$WORK_DIR/motherduck-duckdb-datasource-readonly"
mkdir -p "$DIST_DIR"

# Copy built files
cp gpx_duckdb_datasource_linux_amd64 "$DIST_DIR/"
cp -r dist/* "$DIST_DIR/"
cp plugin.json "$DIST_DIR/"
cp README.md "$DIST_DIR/" 2>/dev/null || true

echo ""
echo "=========================================="
echo "✅ Build Complete!"
echo "=========================================="
echo ""
echo "Plugin built at: $DIST_DIR"
echo ""
echo "To install on your server:"
echo "1. Stop Grafana:"
echo "   sudo systemctl stop grafana-server"
echo ""
echo "2. Backup existing plugin:"
echo "   sudo mv /var/lib/grafana/plugins/motherduck-duckdb-datasource /var/lib/grafana/plugins/motherduck-duckdb-datasource.backup"
echo ""
echo "3. Copy new plugin to server:"
echo "   scp -r $DIST_DIR root@grafana.safecast.jp:/var/lib/grafana/plugins/motherduck-duckdb-datasource"
echo ""
echo "4. Set permissions:"
echo "   sudo chown -R grafana:grafana /var/lib/grafana/plugins/motherduck-duckdb-datasource"
echo ""
echo "5. Start Grafana:"
echo "   sudo systemctl start grafana-server"
echo ""
