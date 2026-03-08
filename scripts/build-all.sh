#!/bin/bash
# Build all packages in dependency order
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$PROJECT_ROOT/repo"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[BUILD]${NC} $*"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $*"; }
log_err() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--output) OUTPUT_DIR="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Parse dependencies.conf and build in order
build_packages() {
    local deps_file="$SCRIPT_DIR/dependencies.conf"
    local built=0 failed=0
    
    [ -f "$deps_file" ] || { log_err "dependencies.conf not found"; exit 1; }
    
    mkdir -p "$OUTPUT_DIR"
    
    log "Output directory: $OUTPUT_DIR"
    log "Reading build order from dependencies.conf..."
    
    while IFS='|' read -r name version depends aur_url build_opts issues || [ -n "$name" ]; do
        # Skip comments and empty lines
        [[ -z "$name" || "$name" =~ ^# ]] && continue
        
        # Skip notes
        [[ "$name" =~ ^NOTE: ]] && continue
        
        # Find package directory
        local pkgdir=""
        for dir in "$PROJECT_ROOT/packages/dependencies/$name" "$PROJECT_ROOT/packages/$name"; do
            [ -d "$dir" ] && { pkgdir="$dir"; break; }
        done
        
        [ -d "$pkgdir" ] || { log_err "Package directory not found: $name"; ((failed++)); continue; }
        [ -f "$pkgdir/PKGBUILD" ] || { log_err "PKGBUILD not found: $name"; ((failed++)); continue; }
        
        log "Building: $name"
        
        # Build the package
        if (cd "$pkgdir" && makepkg -sf --noconfirm --nocheck); then
            # Move built package to output
            mv "$pkgdir"/*.pkg.tar.* "$OUTPUT_DIR/" 2>/dev/null || true
            
            # Install for subsequent builds
            local pkg_file=$(ls "$OUTPUT_DIR/${name}"*.pkg.tar.* 2>/dev/null | head -1)
            [ -f "$pkg_file" ] && sudo pacman -U "$pkg_file" --noconfirm
            
            log_ok "$name"
            ((built++))
        else
            log_err "Failed to build: $name"
            ((failed++))
        fi
    done < "$deps_file"
    
    echo ""
    log "Summary: $built built, $failed failed"
    
    [ $failed -gt 0 ] && exit 1
    log_ok "All packages built successfully!"
}

# Check multilib is enabled
check_multilib() {
    if ! pacman -Sl multilib &>/dev/null; then
        log_err "Multilib repository not enabled"
        log "Add to /etc/pacman.conf:"
        log "  [multilib]"
        log "  Include = /etc/pacman.d/mirrorlist"
        exit 1
    fi
}

check_multilib
build_packages
