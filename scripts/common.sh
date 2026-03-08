#!/usr/bin/env bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $*"
    fi
}

run_cmd() {
    local cmd="$*"
    log_debug "Executing: $cmd"
    if eval "$cmd"; then
        log_debug "Command succeeded: $cmd"
        return 0
    else
        log_error "Command failed: $cmd"
        return 1
    fi
}

run_cmd_silent() {
    local cmd="$*"
    log_debug "Executing (silent): $cmd"
    if eval "$cmd" > /dev/null 2>&1; then
        return 0
    else
        log_error "Command failed: $cmd"
        return 1
    fi
}

check_command() {
    local cmd="$1"
    local package="${2:-$1}"
    
    if command -v "$cmd" &> /dev/null; then
        log_debug "Command found: $cmd"
        return 0
    else
        log_error "Command not found: $cmd"
        log_info "Install with: sudo pacman -S $package"
        return 1
    fi
}

check_commands() {
    local failed=0
    for cmd in "$@"; do
        if ! check_command "$cmd"; then
            failed=1
        fi
    done
    return $failed
}

check_multilib() {
    log_info "Checking multilib repository..."
    
    if pacman -Sl multilib &> /dev/null; then
        log_success "Multilib repository is enabled"
        return 0
    fi
    
    log_warn "Multilib repository not enabled"
    log_info "Attempting to enable multilib..."
    
    if grep -q "^\[multilib\]" /etc/pacman.conf; then
        log_info "Multilib section found, checking Include line..."
        if grep -A1 "^\[multilib\]" /etc/pacman.conf | grep -q "^Include"; then
            log_success "Multilib configured correctly"
            pacman -Sy
            return 0
        fi
    fi
    
    log_info "Adding multilib to pacman.conf..."
    cat << EOF >> /etc/pacman.conf

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
    
    pacman -Sy
    log_success "Multilib repository enabled"
    return 0
}

get_pkg_version() {
    local pkgbuild="${1:-PKGBUILD}"
    
    if [[ ! -f "$pkgbuild" ]]; then
        log_error "PKGBUILD not found: $pkgbuild"
        return 1
    fi
    
    source "$pkgbuild" 2>/dev/null || true
    
    if [[ -n "${pkgver:-}" ]]; then
        if [[ -n "${pkgrel:-}" ]]; then
            echo "${pkgver}-${pkgrel}"
        else
            echo "${pkgver}"
        fi
        return 0
    fi
    
    grep -E "^pkgver=" "$pkgbuild" | cut -d'=' -f2 | tr -d "'" | tr -d '"'
}

get_pkg_name() {
    local pkgbuild="${1:-PKGBUILD}"
    
    if [[ ! -f "$pkgbuild" ]]; then
        log_error "PKGBUILD not found: $pkgbuild"
        return 1
    fi
    
    grep -E "^pkgname=" "$pkgbuild" | cut -d'=' -f2 | tr -d "'" | tr -d '"'
}

detect_build_error() {
    local logfile="${1:-build.log}"
    
    if [[ ! -f "$logfile" ]]; then
        log_warn "Log file not found: $logfile"
        return 1
    fi
    
    log_info "Analyzing build log for errors..."
    
    local errors=()
    
    if grep -qi "error:.*not found" "$logfile"; then
        errors+=("Missing files or dependencies")
    fi
    
    if grep -qi "undefined reference" "$logfile"; then
        errors+=("Undefined references (linker errors)")
    fi
    
    if grep -qi "cannot find -l" "$logfile"; then
        errors+=("Missing libraries")
    fi
    
    if grep -qi "fatal error:" "$logfile"; then
        errors+=("Fatal compilation errors")
    fi
    
    if grep -qi "permission denied" "$logfile"; then
        errors+=("Permission issues")
    fi
    
    if grep -qi "out of memory\|killed" "$logfile"; then
        errors+=("Memory issues")
    fi
    
    if grep -qi "missing dependency" "$logfile"; then
        errors+=("Missing package dependencies")
    fi
    
    if grep -qi "pkg-config.*not found\|Package.*not found" "$logfile"; then
        errors+=("Missing pkg-config dependencies")
    fi
    
    if grep -qi "meson.*error\|ninja.*failed" "$logfile"; then
        errors+=("Meson/Ninja build errors")
    fi
    
    if [[ ${#errors[@]} -eq 0 ]]; then
        log_warn "No specific error patterns detected"
        log_info "Last 20 lines of build log:"
        tail -20 "$logfile"
        return 1
    fi
    
    log_error "Detected error types:"
    for err in "${errors[@]}"; do
        echo "  - $err"
    done
    
    return 0
}

is_installed() {
    local package="$1"
    pacman -Qi "$package" &> /dev/null
}

install_if_missing() {
    local package="$1"
    local reason="${2:-}"
    
    if is_installed "$package"; then
        log_debug "$package is already installed"
        return 0
    fi
    
    log_info "Installing $package... ${reason:+($reason)}"
    sudo pacman -S --noconfirm "$package"
}

build_package() {
    local pkgdir="$1"
    local output_dir="${2:-$PROJECT_ROOT/releases}"
    
    if [[ ! -d "$pkgdir" ]]; then
        log_error "Package directory not found: $pkgdir"
        return 1
    fi
    
    if [[ ! -f "$pkgdir/PKGBUILD" ]]; then
        log_error "PKGBUILD not found in $pkgdir"
        return 1
    fi
    
    local pkgname
    pkgname=$(get_pkg_name "$pkgdir/PKGBUILD")
    log_info "Building package: $pkgname"
    
    mkdir -p "$output_dir"
    
    (
        cd "$pkgdir"
        makepkg -sf --noconfirm
        
        for pkg in *.pkg.tar.*; do
            [[ -f "$pkg" ]] || continue
            mv "$pkg" "$output_dir/"
            log_success "Package built: $pkg"
        done
    )
}

get_build_order() {
    local deps_file="${1:-$SCRIPT_DIR/dependencies.conf}"
    
    if [[ ! -f "$deps_file" ]]; then
        log_warn "Dependencies file not found, using default order"
        find "$PROJECT_ROOT/packages" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;
        return
    fi
    
    grep -E "^[a-z]" "$deps_file" | grep -v "^#" | cut -d'|' -f1 | tr -d ' '
}

ensure_sudo() {
    if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
        log_error "This script requires sudo access"
        return 1
    fi
}

cleanup() {
    log_info "Cleaning up..."
    find "$PROJECT_ROOT" -type d -name "pkg" -exec rm -rf {} + 2>/dev/null || true
    find "$PROJECT_ROOT" -type d -name "src" -exec rm -rf {} + 2>/dev/null || true
}

trap cleanup EXIT

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Common functions loaded. Source this file to use functions."
    echo "Available functions:"
    echo "  log_info, log_error, log_success, log_warn, log_debug"
    echo "  run_cmd, run_cmd_silent"
    echo "  check_command, check_commands"
    echo "  check_multilib"
    echo "  get_pkg_version, get_pkg_name"
    echo "  detect_build_error"
    echo "  is_installed, install_if_missing"
    echo "  build_package"
    echo "  get_build_order"
fi
