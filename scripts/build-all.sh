#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

CLEAN=0
FORCE=0
VERBOSE=0
JOBS=$(nproc)
NO_CHECK=0

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Build all packages in dependency order.

Options:
    -h          Show this help message
    -c          Clean build directories before building
    -f          Force rebuild even if package exists
    -v          Verbose output
    -j N        Number of parallel jobs (default: $JOBS)
    --no-check  Skip package checks (makepkg --nocheck)

Environment:
    DEBUG=1     Enable debug output

Examples:
    $(basename "$0")              Build all packages
    $(basename "$0") -c -v        Clean build with verbose output
    $(basename "$0") -j 4 -f      Force rebuild with 4 jobs
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h) show_help; exit 0 ;;
            -c) CLEAN=1 ;;
            -f) FORCE=1 ;;
            -v) VERBOSE=1; export DEBUG=1 ;;
            -j) JOBS="$2"; shift ;;
            --no-check) NO_CHECK=1 ;;
            *) log_error "Unknown option: $1"; show_help; exit 1 ;;
        esac
        shift
    done
}

check_required_tools() {
    log_info "Checking required tools..."
    local missing=0
    
    for tool in makepkg pacman meson ninja; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "Required tool not found: $tool"
            missing=1
        else
            log_debug "Found: $tool"
        fi
    done
    
    if [[ $missing -eq 1 ]]; then
        log_error "Install missing tools with: sudo pacman -S base-devel meson ninja"
        return 1
    fi
    
    log_success "All required tools available"
}

verify_multilib() {
    check_multilib || {
        log_error "Failed to verify multilib repository"
        return 1
    }
}

parse_dependencies() {
    local deps_file="$SCRIPT_DIR/dependencies.conf"
    
    if [[ ! -f "$deps_file" ]]; then
        log_error "Dependencies file not found: $deps_file"
        return 1
    fi
    
    local packages=()
    while IFS='|' read -r name version depends aur_url build_opts issues || [[ -n "$name" ]]; do
        [[ -z "$name" ]] && continue
        [[ "$name" =~ ^# ]] && continue
        packages+=("$name")
    done < <(cat "$deps_file")
    
    printf '%s\n' "${packages[@]}"
}

get_package_depends() {
    local pkg="$1"
    local deps_file="$SCRIPT_DIR/dependencies.conf"
    
    while IFS='|' read -r name version depends aur_url build_opts issues || [[ -n "$name" ]]; do
        [[ -z "$name" ]] && continue
        [[ "$name" =~ ^# ]] && continue
        if [[ "$name" == "$pkg" ]]; then
            echo "$depends"
            return
        fi
    done < <(cat "$deps_file")
}

topological_sort() {
    local packages=("$@")
    declare -A visited
    declare -A in_stack
    local result=()
    
    visit() {
        local pkg="$1"
        
        if [[ -n "${in_stack[$pkg]:-}" ]]; then
            log_error "Circular dependency detected involving: $pkg"
            return 1
        fi
        
        if [[ -n "${visited[$pkg]:-}" ]]; then
            return 0
        fi
        
        in_stack[$pkg]=1
        
        local deps
        deps=$(get_package_depends "$pkg")
        
        if [[ -n "$deps" ]]; then
            IFS=',' read -ra dep_array <<< "$deps"
            for dep in "${dep_array[@]}"; do
                dep=$(echo "$dep" | tr -d ' ')
                [[ -z "$dep" ]] && continue
                for p in "${packages[@]}"; do
                    if [[ "$p" == "$dep" ]]; then
                        visit "$dep" || return 1
                        break
                    fi
                done
            done
        fi
        
        unset 'in_stack[$pkg]'
        visited[$pkg]=1
        result+=("$pkg")
    }
    
    for pkg in "${packages[@]}"; do
        visit "$pkg" || return 1
    done
    
    printf '%s\n' "${result[@]}"
}

clean_package() {
    local pkgdir="$1"
    
    log_info "Cleaning $pkgdir..."
    rm -rf "$pkgdir"/pkg "$pkgdir"/src
    rm -f "$pkgdir"/*.pkg.tar.*
}

build_package_full() {
    local pkgname="$1"
    local pkgdir=""
    
    if [[ -d "$PROJECT_ROOT/packages/dependencies/$pkgname" ]]; then
        pkgdir="$PROJECT_ROOT/packages/dependencies/$pkgname"
    elif [[ -d "$PROJECT_ROOT/packages/$pkgname" ]]; then
        pkgdir="$PROJECT_ROOT/packages/$pkgname"
    else
        log_error "Package directory not found for: $pkgname"
        log_error "Checked: $PROJECT_ROOT/packages/dependencies/$pkgname"
        log_error "Checked: $PROJECT_ROOT/packages/$pkgname"
        return 1
    fi
    
    if [[ ! -f "$pkgdir/PKGBUILD" ]]; then
        log_error "PKGBUILD not found in $pkgdir"
        return 1
    fi
    
    if [[ $CLEAN -eq 1 ]]; then
        clean_package "$pkgdir"
    fi
    
    local pkg_pattern="${pkgname}-*.pkg.tar.*"
    local existing_pkgs=()
    
    shopt -s nullglob
    existing_pkgs=("$PROJECT_ROOT/releases"/$pkg_pattern)
    shopt -u nullglob
    
    if [[ ${#existing_pkgs[@]} -gt 0 ]] && [[ $FORCE -eq 0 ]]; then
        log_info "Package already built: $pkgname (use -f to force rebuild)"
        return 0
    fi
    
    log_info "Building: $pkgname"
    
    local makepkg_opts="-sf"
    [[ $VERBOSE -eq 1 ]] && makepkg_opts+=" -L"
    [[ $NO_CHECK -eq 1 ]] && makepkg_opts+=" --nocheck"
    
    local logfile="$PROJECT_ROOT/releases/build-${pkgname}.log"
    mkdir -p "$PROJECT_ROOT/releases"
    
    (
        cd "$pkgdir"
        
        if [[ $VERBOSE -eq 1 ]]; then
            makepkg $makepkg_opts 2>&1 | tee "$logfile"
        else
            makepkg $makepkg_opts > "$logfile" 2>&1
        fi
        
        for pkg in *.pkg.tar.*; do
            [[ -f "$pkg" ]] || continue
            mv "$pkg" "$PROJECT_ROOT/releases/"
            log_success "Package built: $pkg"
        done
    )
    
    for pkg in "$PROJECT_ROOT/releases"/${pkgname}-*.pkg.tar.*; do
        [[ -f "$pkg" ]] || continue
        log_info "Installing $pkg so subsequent builds can find it..."
        sudo pacman -U "$pkg" --noconfirm
        break
    done
    
    return $?
}

report_error() {
    local pkgname="$1"
    local logfile="$PROJECT_ROOT/releases/build-${pkgname}.log"
    
    if [[ -f "$logfile" ]]; then
        log_error "Build failed for: $pkgname"
        log_info "Analyzing build log..."
        detect_build_error "$logfile"
        
        log_info "Full log available at: $logfile"
        log_info "Run scripts/detect-errors.sh -f $logfile for fix suggestions"
    else
        log_error "No build log found for: $pkgname"
    fi
}

main() {
    parse_args "$@"
    
    log_info "Starting build process..."
    log_info "Project root: $PROJECT_ROOT"
    log_info "Jobs: $JOBS"
    
    check_required_tools || exit 1
    verify_multilib || exit 1
    
    log_info "Parsing dependencies..."
    local packages
    mapfile -t packages < <(parse_dependencies)
    
    if [[ ${#packages[@]} -eq 0 ]]; then
        log_error "No packages found in dependencies.conf"
        exit 1
    fi
    
    log_info "Found ${#packages[@]} packages to build"
    
    log_info "Resolving build order..."
    local build_order
    mapfile -t build_order < <(topological_sort "${packages[@]}")
    
    log_info "Build order:"
    for pkg in "${build_order[@]}"; do
        echo "  - $pkg"
    done
    
    local failed=0
    local built=0
    local skipped=0
    declare -a failed_packages=()
    
    for pkg in "${build_order[@]}"; do
        if build_package_full "$pkg"; then
            ((built++)) || true
        else
            ((failed++)) || true
            failed_packages+=("$pkg")
            report_error "$pkg"
        fi
    done
    
    echo ""
    log_info "Build summary:"
    log_success "Built: $built"
    [[ $skipped -gt 0 ]] && log_warn "Skipped: $skipped"
    
    if [[ $failed -gt 0 ]]; then
        log_error "Failed: $failed"
        log_error "Failed packages: ${failed_packages[*]}"
        exit 1
    fi
    
    log_success "All packages built successfully!"
}

main "$@"
