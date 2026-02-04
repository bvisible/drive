#!/bin/bash
# Deploy pre-built frontend assets from GitHub Releases
#
# This script downloads the latest pre-built frontend assets from GitHub
# and deploys them to the Drive app, avoiding the need for local builds.
#
# Usage:
#   ./scripts/deploy-assets.sh
#
# Requirements:
#   - curl
#   - tar
#   - jq (optional, for better release detection)

set -e

REPO="bvisible/drive"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIVE_ROOT="$(dirname "$SCRIPT_DIR")"
ASSETS_DIR="$DRIVE_ROOT/drive/public"

echo "========================================"
echo "  Frappe Drive - Asset Deployment"
echo "========================================"
echo ""

# Get latest release with assets
echo "Fetching latest release information..."

if command -v jq &> /dev/null; then
    # Use jq for proper JSON parsing
    DOWNLOAD_URL=$(curl -s "https://api.github.com/repos/$REPO/releases" | \
        jq -r '[.[] | select(.assets[].name == "frontend-assets.tar.gz")][0].assets[] | select(.name == "frontend-assets.tar.gz") | .browser_download_url')
else
    # Fallback to grep (less reliable)
    DOWNLOAD_URL=$(curl -s "https://api.github.com/repos/$REPO/releases" | \
        grep -o '"browser_download_url":[[:space:]]*"[^"]*frontend-assets.tar.gz"' | \
        head -1 | \
        sed 's/.*"\(https[^"]*\)".*/\1/')
fi

if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
    echo "WARNING: No pre-built assets found in GitHub releases."
    echo ""
    echo "Options:"
    echo "  1. Build locally: cd frontend && pnpm install && pnpm build"
    echo "  2. Wait for CI to publish assets after merging to main"
    echo "  3. Manually download from GitHub Actions artifacts"
    echo ""
    exit 1
fi

echo "Found pre-built assets: $DOWNLOAD_URL"
echo ""

# Download assets
TEMP_FILE="/tmp/frontend-assets-$$.tar.gz"
echo "Downloading assets..."
curl -L -o "$TEMP_FILE" "$DOWNLOAD_URL"

# Verify download
if [ ! -f "$TEMP_FILE" ] || [ ! -s "$TEMP_FILE" ]; then
    echo "ERROR: Download failed or file is empty."
    exit 1
fi

echo "Download complete ($(du -h "$TEMP_FILE" | cut -f1))"
echo ""

# Backup existing assets (optional)
if [ -d "$ASSETS_DIR/frontend/assets" ]; then
    echo "Backing up existing assets..."
    BACKUP_DIR="$ASSETS_DIR/frontend/assets.backup.$(date +%Y%m%d%H%M%S)"
    mv "$ASSETS_DIR/frontend/assets" "$BACKUP_DIR"
    echo "Backup created: $BACKUP_DIR"
fi

# Extract assets
echo "Extracting assets to $ASSETS_DIR..."
tar -xzf "$TEMP_FILE" -C "$ASSETS_DIR"

# Cleanup
rm -f "$TEMP_FILE"

# Verify extraction
if [ -d "$ASSETS_DIR/frontend/assets" ]; then
    ASSET_COUNT=$(ls -1 "$ASSETS_DIR/frontend/assets" | wc -l)
    echo ""
    echo "SUCCESS: Deployed $ASSET_COUNT asset files."
    echo ""
    echo "Next steps:"
    echo "  1. Run 'bench build --app drive' to update symlinks"
    echo "  2. Restart workers: supervisorctl restart all"
else
    echo "ERROR: Assets extraction failed - frontend/assets directory not found."
    exit 1
fi

echo ""
echo "========================================"
echo "  Deployment Complete"
echo "========================================"
