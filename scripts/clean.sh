#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

CLEAN_ALL=0
CLEAN_PACKAGES=0
CLEAN_SOURCES=0

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Clean build artifacts and caches.

Options:
    -h          Show this help message
    -a          Clean everything (packages, sources, build dirs)
    -p          Clean built packages only
    -s          Clean source caches only

Without options, cleans only pkg/ and src/ directories.

Examples:
    $(basename "$0")              Clean build directories
    $(basename "$0") -a           Clean everything
    $(basename "$0") -p           Clean built packages
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h) show_help; exit 0 ;;
            -a) CLEAN_ALL=1 ;;
            -p) CLEAN_PACKAGES=1 ;;
            -s) CLEAN_SOURCES=1 ;;
            *) log_error "Unknown option: $1"; show_help; exit 1 ;;
        esac
        shift
    done
}

clean_build_dirs() {
    log_info "Cleaning build directories..."
    
    local count=0
    
    while IFS= read -r -d '' dir; do
        log_debug "Removing: $dir"
        rm -rf "$dir"
        ((count++)) || true
    done < <(find "$PROJECT_ROOT/packages" -type d \( -name "pkg" -o -name "src" \) -print0 2>/dev/null)
    
    if [[ $count -eq 0 ]]; then
        log_info "No build directories to clean"
    else
        log_success "Cleaned $count build directories"
    fi
}

clean_packages() {
    log_info "Cleaning built packages..."
    
    local releases_dir="$PROJECT_ROOT/releases"
    
    if [[ ! -d "$releases_dir" ]]; then
        log_info "No releases directory found"
        return 0
    fi
    
    local count=0
    
    for pkg in "$releases_dir"/*.pkg.tar.*; do
        [[ -f "$pkg" ]] || continue
        log_debug "Removing: $pkg"
        rm -f "$pkg"
        ((count++)) || true
    done
    
    if [[ $count -eq 0 ]]; then
        log_info "No packages to clean"
    else
        log_success "Removed $count packages"
    fi
}

clean_sources() {
    log_info "Cleaning source caches..."
    
    local cache_dirs=(
        "$PROJECT_ROOT/.cache"
        "$HOME/.cache/pacman/pkg"
    )
    
    local count=0
    
    for cache_dir in "${cache_dirs[@]}"; do
        if [[ -d "$cache_dir" ]]; then
            log_debug "Cleaning cache: $cache_dir"
            
            for src in "$cache_dir"/*; do
                [[ -e "$src" ]] || continue
                rm -rf "$src"
                ((count++)) || true
            done
        fi
    done
    
    local makepkg_cache
    makepkg_cache=$(makepkg --config /etc/makepkg.conf --printsrcinfo 2>/dev/null | grep -oP 'source.*?= \K.*' | head -1 || echo "$HOME/.cache/makepkg")
    
    if [[ -d "$makepkg_cache" ]]; then
        log_debug "Cleaning makepkg cache: $makepkg_cache"
        for src in "$makepkg_cache"/lib32-*; do
            [[ -e "$src" ]] || continue
            rm -rf "$src"
            ((count++)) || true
        done
    fi
    
    if [[ $count -eq 0 ]]; then
        log_info "No source caches to clean"
    else
        log_success "Cleaned $count source cache entries"
    fi
}

clean_logs() {
    log_info "Cleaning build logs..."
    
    local releases_dir="$PROJECT_ROOT/releases"
    local count=0
    
    if [[ -d "$releases_dir" ]]; then
        for log in "$releases_dir"/*.log; do
            [[ -f "$log" ]] || continue
            rm -f "$log"
            ((count++)) || true
        done
    fi
    
    if [[ $count -eq 0 ]]; then
        log_info "No logs to clean"
    else
        log_success "Removed $count log files"
    fi
}

main() {
    parse_args "$@"
    
    log_info "Starting cleanup..."
    log_info "Project root: $PROJECT_ROOT"
    
    if [[ $CLEAN_ALL -eq 1 ]]; then
        clean_build_dirs
        clean_packages
        clean_sources
        clean_logs
    elif [[ $CLEAN_PACKAGES -eq 1 ]]; then
        clean_packages
    elif [[ $CLEAN_SOURCES -eq 1 ]]; then
        clean_sources
    else
        clean_build_dirs
    fi
    
    log_success "Cleanup complete"
}

main "$@"
