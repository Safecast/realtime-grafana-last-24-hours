#!/bin/bash

# -----------------------------------------------------------------------------
# Script: deploy-to-server.sh
# Description: Deploy simple flip-flop approach to production server
# Usage: ./deploy-to-server.sh
# -----------------------------------------------------------------------------

SERVER="root@grafana.safecast.jp"
SERVER_PATH="/home/grafana.safecast.jp/public_html"

echo "=========================================="
echo "Server Deployment Helper - Simple Flip-Flop"
echo "=========================================="
echo ""
echo "This script will help you deploy the simple flip-flop"
echo "approach to grafana.safecast.jp"
echo ""

# Step 1: Verify local changes are committed
echo "Step 1: Checking local git status..."
if [[ -n $(git status -s) ]]; then
    echo "❌ You have uncommitted changes!"
    echo "   Please commit and push before deploying."
    git status -s
    exit 1
else
    echo "✅ Local repo is clean"
fi

# Step 2: Verify we're up to date with remote
echo ""
echo "Step 2: Checking if local is up to date with remote..."
git fetch
LOCAL=$(git rev-parse @)
REMOTE=$(git rev-parse @{u})

if [ $LOCAL != $REMOTE ]; then
    echo "❌ Local is not up to date with remote!"
    echo "   Please pull or push changes first."
    exit 1
else
    echo "✅ Local is up to date with remote"
fi

# Step 3: Check SSH connection
echo ""
echo "Step 3: Testing SSH connection to server..."
if ssh -o ConnectTimeout=5 $SERVER "echo ''" 2>/dev/null; then
    echo "✅ SSH connection works"
else
    echo "❌ Cannot connect to $SERVER"
    echo "   Check your SSH keys and network connection"
    exit 1
fi

# Step 4: Check if script exists locally
echo ""
echo "Step 4: Verifying update-flipflop-simple.sh exists..."
if [ -f "update-flipflop-simple.sh" ]; then
    echo "✅ Script found locally"
else
    echo "❌ update-flipflop-simple.sh not found!"
    exit 1
fi

# Step 5: Show deployment commands
echo ""
echo "=========================================="
echo "✅ Pre-flight checks passed!"
echo "=========================================="
echo ""
echo "Ready to deploy! You have two options:"
echo ""
echo "OPTION 1: Follow the detailed guide (RECOMMENDED)"
echo "  Open: SERVER_DEPLOYMENT_SIMPLE.md"
echo "  This walks you through each step with verification"
echo ""
echo "OPTION 2: Quick pull latest code to server"
echo "  Run: ssh $SERVER 'cd $SERVER_PATH && git pull origin main && chmod +x update-flipflop-simple.sh'"
echo "  Then follow steps 3-11 in SERVER_DEPLOYMENT_SIMPLE.md"
echo ""

# Ask if user wants to pull latest code
echo ""
read -p "Pull latest code to server now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "Pulling latest code to server..."
    ssh $SERVER "cd $SERVER_PATH && git pull origin main && chmod +x update-flipflop-simple.sh"
    echo ""
    echo "✅ Code pulled successfully!"
    echo ""
    echo "Next steps:"
    echo "  1. Follow SERVER_DEPLOYMENT_SIMPLE.md from Step 3"
    echo "  2. Or SSH to server: ssh $SERVER"
    echo "  3. Then run: cd $SERVER_PATH && cat SERVER_DEPLOYMENT_SIMPLE.md"
else
    echo ""
    echo "Skipped code pull. You can pull manually later."
fi

# Ask if user wants to open the deployment guide
echo ""
read -p "Open SERVER_DEPLOYMENT_SIMPLE.md now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if command -v less &> /dev/null; then
        less SERVER_DEPLOYMENT_SIMPLE.md
    elif command -v more &> /dev/null; then
        more SERVER_DEPLOYMENT_SIMPLE.md
    else
        cat SERVER_DEPLOYMENT_SIMPLE.md
    fi
fi

echo ""
echo "Good luck with the deployment! 🚀"
echo ""
echo "Quick reference:"
echo "  - Deployment guide: SERVER_DEPLOYMENT_SIMPLE.md"
echo "  - SSH to server: ssh $SERVER"
echo "  - Server path: $SERVER_PATH"
echo "  - Grafana URL: https://grafana.safecast.jp"
echo ""
