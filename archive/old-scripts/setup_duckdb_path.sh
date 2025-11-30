#!/bin/bash

# Script to permanently add DuckDB to PATH on the server

echo "Setting up permanent PATH for DuckDB..."

# Option 1: Add to root's .bashrc (for root user only)
echo "Adding to /root/.bashrc..."
echo '' >> /root/.bashrc
echo '# Add DuckDB to PATH' >> /root/.bashrc
echo 'export PATH=/root/.local/bin:$PATH' >> /root/.bashrc

# Option 2: Add to /etc/profile.d/ (for all users - system-wide)
echo "Creating /etc/profile.d/duckdb.sh for system-wide access..."
cat > /etc/profile.d/duckdb.sh << 'EOF'
#!/bin/bash
# Add DuckDB to PATH for all users
export PATH=/root/.local/bin:$PATH
EOF
chmod +x /etc/profile.d/duckdb.sh

# Option 3: For specific user (if not root)
# Uncomment and modify if needed:
# echo 'export PATH=/root/.local/bin:$PATH' >> ~/.bashrc

echo ""
echo "Setup complete! Choose one of these to apply changes:"
echo ""
echo "1. For current session only:"
echo "   source /root/.bashrc"
echo ""
echo "2. For new terminals:"
echo "   Just open a new terminal/SSH session"
echo ""
echo "3. To verify after applying:"
echo "   which duckdb"
echo "   duckdb --version"
