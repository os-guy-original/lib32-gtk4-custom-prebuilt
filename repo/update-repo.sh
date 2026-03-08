#!/bin/bash
set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_DIR"

echo "Updating repository database..."
echo "Repo directory: $REPO_DIR"

# Check if releases directory exists
if [ ! -d "../releases" ]; then
    echo "ERROR: releases directory not found at ../releases"
    exit 1
fi

# Count packages
PKG_COUNT=$(ls ../releases/*.pkg.tar.zst 2>/dev/null | wc -l)
echo "Found $PKG_COUNT packages to add"

if [ "$PKG_COUNT" -eq 0 ]; then
    echo "WARNING: No packages found in releases/"
    exit 0
fi

# Remove old database files
rm -f lib32-gtk4-custom.db lib32-gtk4-custom.db.tar.gz lib32-gtk4-custom.files lib32-gtk4-custom.files.tar.gz

# Add packages
for pkg in ../releases/*.pkg.tar.zst; do
    [ -f "$pkg" ] || continue
    echo "Adding: $(basename $pkg)"
    repo-add lib32-gtk4-custom.db.tar.gz "$pkg"
done

# Verify files were created
if [ -f "lib32-gtk4-custom.db.tar.gz" ]; then
    echo "SUCCESS: Repository database created"
    ls -la lib32-gtk4-custom.db.tar.gz
else
    echo "ERROR: Repository database was not created"
    exit 1
fi
