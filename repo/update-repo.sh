#!/bin/bash
# Update pacman repository database from packages in current directory
set -e

REPO_NAME="lib32-gtk4-custom"

echo "=== Updating Repository Database ==="

# Find packages in current directory
mapfile -t PACKAGES < <(find . -maxdepth 1 -name "*.pkg.tar.zst" -type f 2>/dev/null | sort)
PKG_COUNT=${#PACKAGES[@]}

echo "Found $PKG_COUNT package(s)"

if [ "$PKG_COUNT" -eq 0 ]; then
    echo "WARNING: No packages found"
    exit 0
fi

# Remove old database and symlinks
rm -f "$REPO_NAME".db.tar.gz "$REPO_NAME".files.tar.gz
rm -f "$REPO_NAME".db "$REPO_NAME".files
rm -f "$REPO_NAME".db.tar.gz.old "$REPO_NAME".files.tar.gz.old

# Create new database
for pkg in "${PACKAGES[@]}"; do
    echo "Adding: $(basename "$pkg")"
    repo-add "$REPO_NAME".db.tar.gz "$pkg"
done

# Remove symlinks created by repo-add (GitHub raw URLs need actual files)
rm -f "$REPO_NAME".db "$REPO_NAME".files
rm -f "$REPO_NAME".db.tar.gz.old "$REPO_NAME".files.tar.gz.old

# Copy .tar.gz to .db and .files (pacman expects these filenames)
cp "$REPO_NAME".db.tar.gz "$REPO_NAME".db
cp "$REPO_NAME".files.tar.gz "$REPO_NAME".files

echo ""
ls -lh "$REPO_NAME".db "$REPO_NAME".files
echo "SUCCESS: Database updated"
