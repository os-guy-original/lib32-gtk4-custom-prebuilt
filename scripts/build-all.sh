#!/bin/bash
# Build all packages in dependency order
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$PROJECT_ROOT/repo"

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
while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--output) OUTPUT_DIR="$2"; shift 2 ;;
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

get_package_count() {
    local deps_file="$SCRIPT_DIR/dependencies.conf"
    local count=0
    while IFS='|' read -r name _; do
        [[ -z "$name" || "$name" =~ ^# || "$name" =~ ^NOTE: ]] && continue
        count=$((count + 1))
    done < "$deps_file"
    echo $count
}

build_packages() {
    local deps_file="$SCRIPT_DIR/dependencies.conf"
    local built=0 failed=0 skipped=0
    local total
    local start_time=$(date +%s)
    
    [ -f "$deps_file" ] || { error "dependencies.conf not found"; exit 1; }
    
    total=$(get_package_count)
    
    step "Starting build process"
    info "Output directory: $OUTPUT_DIR"
    info "Packages to build: $total"
    
    mkdir -p "$OUTPUT_DIR"
    
    local current=0
    while IFS='|' read -r name version depends aur_url build_opts issues || [ -n "$name" ]; do
        # Skip comments and empty lines
        [[ -z "$name" || "$name" =~ ^# ]] && continue
        [[ "$name" =~ ^NOTE: ]] && continue
        
        current=$((current + 1))
        
        # Find package directory
        local pkgdir=""
        for dir in "$PROJECT_ROOT/packages/dependencies/$name" "$PROJECT_ROOT/packages/$name"; do
            [ -d "$dir" ] && { pkgdir="$dir"; break; }
        done
        
        if [ ! -d "$pkgdir" ]; then
            error "Package directory not found: $name"
            failed=$((failed + 1))
            continue
        fi
        
        if [ ! -f "$pkgdir/PKGBUILD" ]; then
            error "PKGBUILD not found: $name"
            failed=$((failed + 1))
            continue
        fi
        
        step "Building $name ($current/$total)"
        info "Version: ${version:-unknown}"
        if [ -n "$depends" ]; then
            info "Depends on: $depends"
        fi
        
        local pkg_start=$(date +%s)
        
        # Build the package
        if (cd "$pkgdir" && makepkg -sf --noconfirm --nocheck 2>&1 | while read -r line; do
            case "$line" in
                "==> Making package:"*|"==> Starting build"*|"==> Finished making:"*)
                    echo "    $line"
                    ;;
                "==> Creating package"*|"==> Entering fakeroot"*)
                    echo "    $line"
                    ;;
                *"error:"*|*"Error:"*|*"ERROR:"*)
                    echo "    $line"
                    ;;
            esac
        done); then
            # Move built package to output
            mv "$pkgdir"/*.pkg.tar.* "$OUTPUT_DIR/" 2>/dev/null || true
            
            # Install for subsequent builds (ignore errors)
            local pkg_file=$(ls "$OUTPUT_DIR/${name}"*.pkg.tar.* 2>/dev/null | grep -v debug | head -1)
            if [ -f "$pkg_file" ]; then
                info "Installing $name for subsequent builds..."
                sudo pacman -U "$pkg_file" --noconfirm --overwrite '*' 2>/dev/null || info "Note: Package may already be installed"
            fi
            
            local pkg_end=$(date +%s)
            local duration=$((pkg_end - pkg_start))
            
            ok "$name completed in ${duration}s"
            built=$((built + 1))
        else
            error "Failed to build: $name"
            failed=$((failed + 1))
        fi
    done < "$deps_file"
    
    local end_time=$(date +%s)
    local total_time=$((end_time - start_time))
    
    echo ""
    step "Build Summary"
    echo ""
    echo "  Built:   $built"
    [ $failed -gt 0 ] && echo -e "  ${RED}Failed:  $failed${NC}"
    echo "  Time:    ${total_time}s"
    echo ""
    
    if [ $failed -gt 0 ]; then
        error "Build completed with $failed failure(s)"
        exit 1
    fi
    
    ok "All $built packages built successfully in ${total_time}s"
}

# Main
echo ""
echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}   lib32-prebuilts Build System${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""

check_multilib
build_packages
