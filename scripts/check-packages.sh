#!/bin/bash
# Check which packages need to be rebuilt

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/common.sh"

NEEDS_BUILD=()
ALREADY_BUILT=()

# Get build order
packages=$(get_build_order)

while IFS= read -r pkgname; do
    [ -z "$pkgname" ] && continue
    
    pkginfo=$(get_package_info "$pkgname")
    IFS='|' read -r _ pkgver depends notes <<< "$pkginfo"
    
    if check_package_valid "$pkgname" "$pkgver"; then
        ALREADY_BUILT+=("$pkgname")
        echo "✓ $pkgname - up to date"
    else
        NEEDS_BUILD+=("$pkgname")
        echo "✗ $pkgname - needs build"
    fi
done <<< "$packages"

echo ""
echo "Summary:"
echo "  Up to date: ${#ALREADY_BUILT[@]}"
echo "  Needs build: ${#NEEDS_BUILD[@]}"

if [ ${#NEEDS_BUILD[@]} -gt 0 ]; then
    echo ""
    echo "Packages to build: ${NEEDS_BUILD[*]}"
    exit 1
fi

exit 0
