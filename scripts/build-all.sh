#!/bin/bash
# Build all packages in dependency order
# STRICT MODE - stops on first failure

set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_DIR="$PROJECT_ROOT/repo"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
step()  { echo -e "\n${BOLD}${BLUE}==>${NC} ${BOLD}$*${NC}"; }

# Parse arguments
FORCE_BUILD=0
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force) FORCE_BUILD=1; shift ;;
        *) shift ;;
    esac
done

# Source common functions
source "$SCRIPT_DIR/common.sh"

check_multilib() {
    if ! pacman -Sl multilib &>/dev/null; then
        error "Multilib repository not enabled"
        exit 1
    fi
    info "Multilib repository: OK"
}

# Install package from repo if available
install_from_repo() {
    local pkgname="$1"
    
    # Find any package file matching the name
    for pkgfile in "$REPO_DIR/${pkgname}"-*-x86_64.pkg.tar.zst; do
        # Skip debug packages
        [[ "$pkgfile" == *-debug-* ]] && continue
        [ -f "$pkgfile" ] || continue
        
        info "Installing $pkgname from repo..."
        sudo pacman -U "$pkgfile" --noconfirm --overwrite '*' 2>&1 || {
            warn "Failed to install $pkgname (may already be installed)"
        }
        return 0
    done
    return 1
}

# Install all available packages from repo (for dependency satisfaction)
install_all_from_repo() {
    info "Installing available packages from repo..."
    
    local installed=0
    for pkgfile in "$REPO_DIR"/lib32-*-x86_64.pkg.tar.zst; do
        # Skip debug packages
        [[ "$pkgfile" == *-debug-* ]] && continue
        [ -f "$pkgfile" ] || continue
        
        local pkgname=$(basename "$pkgfile" | sed 's/-[0-9].*//')
        info "Installing $pkgname..."
        sudo pacman -U "$pkgfile" --noconfirm --overwrite '*' 2>&1 || true
        installed=$((installed + 1))
    done
    
    info "Installed $installed packages from repo"
}

# Check if package is built and valid
check_package_valid() {
    local pkgname="$1"
    local pkgver="$2"
    
    local pkgfile=$(ls "$REPO_DIR/${pkgname}-${pkgver}"*-x86_64.pkg.tar.zst 2>/dev/null | grep -v debug | head -1)
    [ -z "$pkgfile" ] && return 1
    [ ! -f "${pkgfile}.sig" ] && return 1
    
    return 0
}

# Build a single package
build_package() {
    local pkgname="$1"
    local pkgver="$2"
    local pkgdir=$(find_pkgdir "$pkgname")
    
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
    
    # Build with -d to skip dependency checks (we handle deps ourselves)
    if makepkg -f --noconfirm --nocheck -d 2>&1 | tee /tmp/build-${pkgname}.log; then
        # Move packages to repo
        mv "$pkgdir"/*.pkg.tar.* "$REPO_DIR/" 2>/dev/null || true
        
        # Install this package for subsequent builds
        install_from_repo "$pkgname" || true
        
        local pkg_end=$(date +%s)
        ok "$pkgname completed in $((pkg_end - pkg_start))s"
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
    
    # First, install all available packages from repo
    # This ensures dependencies are satisfied for subsequent builds
    if [ -d "$REPO_DIR" ] && ls "$REPO_DIR"/*.pkg.tar.zst >/dev/null 2>&1; then
        install_all_from_repo
    fi
    
    # Get build order
    local packages
    packages=$(get_build_order)
    
    local total=$(echo "$packages" | wc -l)
    local current=0
    local built=0
    local skipped=0
    local failed=0
    local start_time=$(date +%s)
    
    info "Total packages: $total"
    
    while IFS= read -r pkgname; do
        [ -z "$pkgname" ] && continue
        current=$((current + 1))
        
        # Get package info
        local pkginfo
        pkginfo=$(get_package_info "$pkgname")
        IFS='|' read -r _ pkgver depends notes <<< "$pkginfo"
        
        info "[$current/$total] Checking $pkgname"
        
        # Check if already built and valid
        if [ $FORCE_BUILD -eq 0 ] && check_package_valid "$pkgname" "$pkgver"; then
            info "Skipping $pkgname - already built and signed"
            # Install it anyway for deps
            install_from_repo "$pkgname" || true
            skipped=$((skipped + 1))
            continue
        fi
        
        # Build it
        if build_package "$pkgname" "$pkgver"; then
            built=$((built + 1))
        else
            failed=$((failed + 1))
            error "Stopping due to build failure: $pkgname"
            exit 1
        fi
    done <<< "$packages"
    
    local end_time=$(date +%s)
    
    echo ""
    step "Build Summary"
    echo ""
    echo "  Built:   $built"
    echo "  Skipped: $skipped"
    [ $failed -gt 0 ] && echo -e "  ${RED}Failed:  $failed${NC}"
    echo "  Time:    $((end_time - start_time))s"
    echo ""
    
    if [ $failed -gt 0 ]; then
        error "Build failed"
        exit 1
    fi
    
    ok "All packages processed successfully"
}

main
