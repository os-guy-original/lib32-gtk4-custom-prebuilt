#!/bin/bash
# Build all packages in dependency order
# Uses packages.conf for configuration

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_DIR="$PROJECT_ROOT/repo"

# Source common functions
source "$SCRIPT_DIR/common.sh"

# Parse arguments
FORCE_BUILD=0
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force) FORCE_BUILD=1; shift ;;
        -h|--help)
            echo "Usage: $0 [-f|--force]"
            echo "  -f, --force  Force rebuild all packages"
            exit 0
            ;;
        *) shift ;;
    esac
done

check_multilib() {
    if ! pacman -Sl multilib &>/dev/null; then
        error "Multilib repository not enabled"
        info "Add to /etc/pacman.conf:"
        info "  [multilib]"
        info "  Include = /etc/pacman.d/mirrorlist"
        exit 1
    fi
    info "Multilib repository: OK"
}

build_package() {
    local pkgname="$1"
    local pkgver="$2"
    local pkgdir
    
    pkgdir=$(find_pkgdir "$pkgname")
    
    if [ -z "$pkgdir" ]; then
        error "Package directory not found: $pkgname"
        return 1
    fi
    
    if [ ! -f "$pkgdir/PKGBUILD" ]; then
        error "PKGBUILD not found: $pkgname"
        return 1
    fi
    
    step "Building $pkgname"
    info "Version: $pkgver"
    
    local pkg_start=$(date +%s)
    
    cd "$pkgdir"
    
    if bash -c "set -o pipefail; makepkg -sf --noconfirm --nocheck 2>&1 | tee /tmp/build-${pkgname}.log"; then
        # Move to repo
        mv "$pkgdir"/*.pkg.tar.* "$REPO_DIR/" 2>/dev/null || true
        
        # Install for subsequent builds
        local pkg_file=$(ls "$REPO_DIR/${pkgname}"*.pkg.tar.* 2>/dev/null | grep -v debug | head -1)
        if [ -f "$pkg_file" ]; then
            info "Installing $pkgname for subsequent builds..."
            sudo pacman -U "$pkg_file" --noconfirm --overwrite '*' 2>/dev/null || info "Package may already be installed"
        fi
        
        local pkg_end=$(date +%s)
        local duration=$((pkg_end - pkg_start))
        
        ok "$pkgname completed in ${duration}s"
        cd "$PROJECT_ROOT"
        return 0
    else
        error "Failed to build: $pkgname"
        cd "$PROJECT_ROOT"
        return 1
    fi
}

main() {
    echo ""
    echo -e "${BOLD}========================================${NC}"
    echo -e "${BOLD}   lib32-prebuilts Build System${NC}"
    echo -e "${BOLD}========================================${NC}"
    echo ""
    
    check_multilib
    
    mkdir -p "$REPO_DIR"
    
    # Get build order
    local packages
    packages=$(get_build_order)
    
    local total=$(echo "$packages" | wc -l)
    local current=0
    local built=0
    local skipped=0
    local failed=0
    local start_time=$(date +%s)
    
    info "Packages to process: $total"
    
    while IFS= read -r pkgname; do
        [ -z "$pkgname" ] && continue
        current=$((current + 1))
        
        # Get package info
        local pkginfo
        pkginfo=$(get_package_info "$pkgname")
        IFS='|' read -r _ pkgver depends notes <<< "$pkginfo"
        
        # Check if already built (unless forced)
        if [ $FORCE_BUILD -eq 0 ] && check_package_valid "$pkgname" "$pkgver"; then
            info "[$current/$total] $pkgname - already built, skipping"
            skipped=$((skipped + 1))
            continue
        fi
        
        info "[$current/$total] $pkgname"
        
        if build_package "$pkgname" "$pkgver"; then
            built=$((built + 1))
        else
            failed=$((failed + 1))
        fi
    done <<< "$packages"
    
    local end_time=$(date +%s)
    local total_time=$((end_time - start_time))
    
    echo ""
    step "Build Summary"
    echo ""
    echo "  Built:   $built"
    echo "  Skipped: $skipped"
    [ $failed -gt 0 ] && echo -e "  ${RED}Failed:  $failed${NC}"
    echo "  Time:    ${total_time}s"
    echo ""
    
    if [ $failed -gt 0 ]; then
        error "Build completed with $failed failure(s)"
        exit 1
    fi
    
    ok "All packages processed in ${total_time}s"
}

main
