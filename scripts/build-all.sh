#!/bin/bash
# Build all packages in dependency order
# STRICT MODE - stops on first failure

set -e

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

source "$SCRIPT_DIR/common.sh"

check_multilib() {
    if ! pacman -Sl multilib &>/dev/null; then
        error "Multilib repository not enabled"
        exit 1
    fi
    info "Multilib repository: OK"
}

install_from_repo() {
    local pkgname="$1"
    for pkgfile in "$REPO_DIR/${pkgname}"-*-x86_64.pkg.tar.zst; do
        [[ "$pkgfile" == *-debug-* ]] && continue
        [ -f "$pkgfile" ] || continue
        info "Installing $pkgname from repo..."
        sudo pacman -U "$pkgfile" --noconfirm --overwrite '*' 2>&1 || true
        return 0
    done
    return 1
}

install_all_from_repo() {
    info "Installing available packages from repo..."
    local installed=0
    for pkgfile in "$REPO_DIR"/lib32-*-x86_64.pkg.tar.zst; do
        [[ "$pkgfile" == *-debug-* ]] && continue
        [ -f "$pkgfile" ] || continue
        local pkgname=$(basename "$pkgfile" | sed 's/-[0-9].*//')
        info "Installing $pkgname..."
        sudo pacman -U "$pkgfile" --noconfirm --overwrite '*' 2>&1 || true
        installed=$((installed + 1))
    done
    info "Installed $installed packages from repo"
}

check_package_valid() {
    local pkgname="$1"
    local pkgver="$2"
    local pkgfile=$(ls "$REPO_DIR/${pkgname}-${pkgver}"*-x86_64.pkg.tar.zst 2>/dev/null | grep -v debug | head -1)
    [ -z "$pkgfile" ] && return 1
    [ ! -f "${pkgfile}.sig" ] && return 1
    return 0
}

build_package() {
    local pkgname="$1"
    local pkgver="$2"
    local pkgdir=$(find_pkgdir "$pkgname")
    
    [ -z "$pkgdir" ] && { error "Package directory not found: $pkgname"; return 1; }
    [ ! -f "$pkgdir/PKGBUILD" ] && { error "PKGBUILD not found: $pkgname"; return 1; }
    
    step "Building $pkgname"
    info "Version: $pkgver"
    
    local pkg_start=$(date +%s)
    
    cd "$pkgdir"
    
    # Run makepkg without tee - let output go directly to stdout
    if makepkg -f --noconfirm --nocheck -d; then
        mv "$pkgdir"/*.pkg.tar.* "$REPO_DIR/" 2>/dev/null || true
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
    
    [ -d "$REPO_DIR" ] && ls "$REPO_DIR"/*.pkg.tar.zst >/dev/null 2>&1 && install_all_from_repo
    
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
        
        local pkginfo
        pkginfo=$(get_package_info "$pkgname")
        IFS='|' read -r _ pkgver depends notes <<< "$pkginfo"
        
        info "[$current/$total] Checking $pkgname"
        
        if [ $FORCE_BUILD -eq 0 ] && check_package_valid "$pkgname" "$pkgver"; then
            info "Skipping $pkgname - already built and signed"
            install_from_repo "$pkgname" || true
            skipped=$((skipped + 1))
            continue
        fi
        
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
    
    [ $failed -gt 0 ] && { error "Build failed"; exit 1; }
    
    ok "All packages processed successfully"
}

main
