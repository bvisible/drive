#!/bin/bash
# One-time setup script to configure pnpm cache on server
# Run this ONCE on each server (osiris, etc.)
#
# This script:
# 1. Creates a persistent pnpm store directory
# 2. Configures pnpm to use it for all future installs
# 3. Enables side-effects-cache to cache compiled native binaries
#
# After running this, 'bench build --app drive' will use the cache automatically.
# First build: ~15 minutes (compiles native modules like canvas)
# Subsequent builds: ~3 minutes (cache hit)

set -e

PNPM_STORE="/var/cache/pnpm-store"

echo "=== Configuration du cache pnpm ==="
echo ""

# Check if running as root or with sudo available
if [ "$EUID" -eq 0 ]; then
    # Running as root
    mkdir -p "$PNPM_STORE"
    # Try to find the actual user (not root)
    REAL_USER="${SUDO_USER:-$USER}"
    if [ "$REAL_USER" != "root" ]; then
        chown "$REAL_USER:$REAL_USER" "$PNPM_STORE"
    fi
else
    # Running as normal user, need sudo for /var/cache
    echo "Creating $PNPM_STORE (requires sudo)..."
    sudo mkdir -p "$PNPM_STORE"
    sudo chown "$USER:$USER" "$PNPM_STORE"
fi

echo "Store directory created: $PNPM_STORE"

# Configure pnpm to use persistent store
echo "Configuring pnpm..."
pnpm config set store-dir "$PNPM_STORE"
pnpm config set side-effects-cache true

echo ""
echo "=== Configuration terminée! ==="
echo ""
echo "Le store pnpm est maintenant dans: $PNPM_STORE"
echo ""
echo "Vérification de la configuration:"
echo "  store-dir: $(pnpm config get store-dir)"
echo "  side-effects-cache: $(pnpm config get side-effects-cache)"
echo ""
echo "Les prochains 'bench build --app drive' utiliseront ce cache."
echo ""
echo "Premier build: ~15 minutes (compile les modules natifs)"
echo "Builds suivants: ~3 minutes (cache hit)"
echo ""
echo "Pour tester:"
echo "  cd $(dirname "$0")/../frontend"
echo "  rm -rf node_modules"
echo "  time pnpm install"
echo "  time NODE_OPTIONS='--max-old-space-size=2048' pnpm build"
