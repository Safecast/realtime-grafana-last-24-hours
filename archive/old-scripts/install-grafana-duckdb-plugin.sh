#!/bin/bash

# -----------------------------------------------------------------------------
# Script: install-grafana-duckdb-plugin.sh
# Description: Helper script to install MotherDuck's DuckDB datasource plugin
#              for Grafana
# -----------------------------------------------------------------------------

set -e

echo "=========================================="
echo "Grafana DuckDB Plugin Installation Helper"
echo "=========================================="
echo ""

# Check if Grafana is installed
if ! command -v grafana-server &> /dev/null; then
    echo "❌ Error: Grafana is not installed."
    exit 1
fi

GRAFANA_VERSION=$(grafana-server -v 2>&1 | grep -oP 'Version \K[0-9.]+' || echo "unknown")
echo "✅ Grafana version: $GRAFANA_VERSION"
echo ""

# Find plugin directory
PLUGIN_DIR="/var/lib/grafana/plugins"
if [ ! -d "$PLUGIN_DIR" ]; then
    echo "⚠️  Default plugin directory not found at $PLUGIN_DIR"
    echo "Please check your Grafana configuration for the plugins directory."
    echo ""
    echo "Run: grep 'plugins' /etc/grafana/grafana.ini"
    exit 1
fi

echo "✅ Plugin directory: $PLUGIN_DIR"
echo ""

# Get latest release version
echo "📦 Fetching latest plugin release..."
LATEST_VERSION=$(curl -s https://api.github.com/repos/motherduckdb/grafana-duckdb-datasource/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "$LATEST_VERSION" ]; then
    echo "❌ Error: Could not fetch latest version."
    echo "Visit: https://github.com/motherduckdb/grafana-duckdb-datasource/releases"
    exit 1
fi

echo "Latest version: $LATEST_VERSION"
echo ""

# Download URL (architecture-independent package)
DOWNLOAD_URL="https://github.com/motherduckdb/grafana-duckdb-datasource/releases/download/${LATEST_VERSION}/motherduck-duckdb-datasource-${LATEST_VERSION#v}.zip"

echo "📥 Download URL: $DOWNLOAD_URL"
echo ""

# Create temporary directory
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"

echo "📥 Downloading plugin..."
if ! curl -L -f -o plugin.zip "$DOWNLOAD_URL"; then
    echo "❌ Error: Download failed."
    echo ""
    echo "GitHub may have redirected or the file doesn't exist."
    echo "Please try downloading manually from:"
    echo "https://github.com/motherduckdb/grafana-duckdb-datasource/releases"
    echo ""
    echo "Manual installation steps:"
    echo "1. Download the zip file for your architecture"
    echo "2. Extract it: unzip motherduck-duckdb-datasource-*.zip"
    echo "3. Copy to plugins: sudo cp -r motherduck-duckdb-datasource /var/lib/grafana/plugins/"
    echo "4. Set permissions: sudo chown -R grafana:grafana /var/lib/grafana/plugins/motherduck-duckdb-datasource"
    rm -rf "$TMP_DIR"
    exit 1
fi

# Verify the download is a valid zip file
if ! file plugin.zip | grep -q "Zip archive"; then
    echo "❌ Error: Downloaded file is not a valid zip archive."
    echo "This might be a GitHub redirect issue."
    echo ""
    echo "File contents:"
    cat plugin.zip
    echo ""
    echo "Please download manually from:"
    echo "https://github.com/motherduckdb/grafana-duckdb-datasource/releases/tag/${LATEST_VERSION}"
    rm -rf "$TMP_DIR"
    exit 1
fi

echo "✅ Download complete"
echo ""

echo "📦 Extracting plugin..."
unzip -q plugin.zip

echo "✅ Plugin extracted"
echo ""

# Copy to plugin directory
echo "📂 Installing plugin to $PLUGIN_DIR..."
echo "This requires sudo privileges..."
echo ""

sudo cp -r motherduck-duckdb-datasource "$PLUGIN_DIR/"
sudo chown -R grafana:grafana "$PLUGIN_DIR/motherduck-duckdb-datasource"

echo "✅ Plugin installed"
echo ""

# Clean up
cd -
rm -rf "$TMP_DIR"

echo "🔧 Configuring Grafana..."
echo ""

# Check if unsigned plugins are allowed
GRAFANA_INI="/etc/grafana/grafana.ini"
if grep -q "allow_loading_unsigned_plugins.*motherduck-duckdb-datasource" "$GRAFANA_INI"; then
    echo "✅ Unsigned plugins already configured"
else
    echo "⚠️  Need to allow unsigned plugins in Grafana configuration"
    echo ""
    echo "Please run as root:"
    echo ""
    echo "sudo bash -c 'echo \"allow_loading_unsigned_plugins = motherduck-duckdb-datasource\" >> /etc/grafana/grafana.ini'"
    echo ""
    echo "Or manually add this line under [plugins] section in /etc/grafana/grafana.ini:"
    echo "allow_loading_unsigned_plugins = motherduck-duckdb-datasource"
    echo ""
fi

echo "🔄 Restarting Grafana..."
echo ""

if sudo systemctl restart grafana-server; then
    echo "✅ Grafana restarted successfully"
else
    echo "⚠️  Failed to restart Grafana. Please restart manually:"
    echo "sudo systemctl restart grafana-server"
fi

echo ""
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Open Grafana: http://localhost:3000"
echo "2. Go to: Configuration → Data Sources → Add data source"
echo "3. Search for 'DuckDB' and select it"
echo "4. Configure the connection:"
echo "   - Name: Safecast Devices"
echo "   - Path: $(pwd)/devices.duckdb"
echo "5. Click 'Save & Test'"
echo ""
echo "📖 Full guide: $(pwd)/GRAFANA_DUCKDB_SETUP.md"
echo "📊 Import dashboard: $(pwd)/grafana-safecast-dashboard.json"
echo ""
