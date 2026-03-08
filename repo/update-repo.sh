#!/bin/bash
set -e

REPO_DIR="$(dirname "$0")"
cd "$REPO_DIR"

# Rebuild repo database
rm -f lib32-gtk4-custom.db lib32-gtk4-custom.db.tar.gz lib32-gtk4-custom.files

# Add packages
for pkg in ../releases/*.pkg.tar.zst; do
    [ -f "$pkg" ] || continue
    repo-add -R lib32-gtk4-custom.db.tar.gz "$pkg"
done

echo "Repository updated with $(ls ../releases/*.pkg.tar.zst 2>/dev/null | wc -l) packages"
