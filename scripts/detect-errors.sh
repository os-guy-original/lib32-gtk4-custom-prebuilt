#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

FIX_MODE=0
REPORT_MODE=0
VERBOSE=0
LOG_FILE=""

declare -A ERROR_PATTERNS=(
    ["missing_dep"]="error:.*not found|cannot find -l|Package '.*' not found"
    ["pkg_config"]="pkg-config.*not found|Package.*not found|Could not find.*package"
    ["include_error"]="fatal error:.*: No such file|error:.*No such file or directory"
    ["link_error"]="undefined reference to|cannot find -l|ld returned|relocation R_X86_64_32"
    ["meson_error"]="meson.*error|ninja: build stopped|Dependency.*not found"
    ["compiler_error"]="error:.*undeclared|error:.*was not declared|error: expected"
    ["objcopy_error"]="objcopy:.*not recognized|objcopy:.*Invalid operation"
    ["memory_error"]="out of memory|killed$|cannot allocate memory"
    ["permission_error"]="Permission denied|permission denied"
)

declare -A ERROR_FIXES=(
    ["missing_dep"]="Install the missing dependency package. Check if a lib32- variant is needed."
    ["pkg_config"]="Install the development package. For lib32 builds, use lib32-* packages."
    ["include_error"]="Install the header package. Usually lib32-*-dev or lib32-*-headers."
    ["link_error"]="Install the library package. Check for lib32- variants of required libraries."
    ["meson_error"]="Check meson.build for dependency requirements. Some dependencies may be optional."
    ["compiler_error"]="Check C/C++ standard version or missing includes."
    ["objcopy_error"]="This is a known issue with lib32 builds. Try applying the objcopy workaround patch."
    ["memory_error"]="Increase available memory or reduce parallel jobs with -j flag."
    ["permission_error"]="Check file permissions or run with appropriate privileges."
)

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [LOG_FILE]

Analyze build logs for common errors and suggest fixes.

Options:
    -h          Show this help message
    -f          Attempt automatic fixes where possible
    -r          Generate detailed error report
    -v          Verbose output

Arguments:
    LOG_FILE    Path to build log file (default: searches recent logs)

Examples:
    $(basename "$0") build.log
    $(basename "$0") -r build.log
    $(basename "$0") -f build.log
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h) show_help; exit 0 ;;
            -f) FIX_MODE=1 ;;
            -r) REPORT_MODE=1 ;;
            -v) VERBOSE=1; export DEBUG=1 ;;
            -*)
                if [[ -z "$LOG_FILE" ]]; then
                    log_error "Unknown option: $1"
                    show_help
                    exit 1
                fi
                ;;
            *)
                if [[ -z "$LOG_FILE" ]]; then
                    LOG_FILE="$1"
                fi
                ;;
        esac
        shift
    done
}

find_latest_log() {
    local log_dir="$PROJECT_ROOT/releases"
    
    if [[ ! -d "$log_dir" ]]; then
        log_error "No releases directory found"
        return 1
    fi
    
    local latest=""
    local latest_time=0
    
    for log in "$log_dir"/*.log; do
        [[ -f "$log" ]] || continue
        local mtime
        mtime=$(stat -c %Y "$log" 2>/dev/null || stat -f %m "$log" 2>/dev/null)
        if [[ $mtime -gt $latest_time ]]; then
            latest_time=$mtime
            latest="$log"
        fi
    done
    
    if [[ -z "$latest" ]]; then
        log_error "No log files found in $log_dir"
        return 1
    fi
    
    echo "$latest"
}

detect_error_type() {
    local logfile="$1"
    local errors=()
    
    for error_type in "${!ERROR_PATTERNS[@]}"; do
        local pattern="${ERROR_PATTERNS[$error_type]}"
        if grep -qiE "$pattern" "$logfile" 2>/dev/null; then
            errors+=("$error_type")
        fi
    done
    
    printf '%s\n' "${errors[@]}"
}

extract_missing_packages() {
    local logfile="$1"
    local packages=()
    
    while read -r line; do
        if [[ "$line" =~ Package[\ \']+([a-zA-Z0-9_-]+) ]]; then
            packages+=("${BASH_REMATCH[1]}")
        elif [[ "$line" =~ cannot\ find\ -l([a-zA-Z0-9_-]+) ]]; then
            packages+=("lib${BASH_REMATCH[1]}")
        elif [[ "$line" =~ error:.*\'([a-zA-Z0-9_-]+)\' ]]; then
            packages+=("${BASH_REMATCH[1]}")
        fi
    done < <(grep -iE "Package.*not found|cannot find -l|error:.*not found" "$logfile" 2>/dev/null || true)
    
    printf '%s\n' "${packages[@]}" | sort -u
}

suggest_lib32_package() {
    local pkg="$1"
    
    if [[ "$pkg" == lib32-* ]]; then
        echo "$pkg"
    elif [[ "$pkg" == lib* ]]; then
        echo "lib32-${pkg#lib}"
    else
        echo "lib32-$pkg"
    fi
}

generate_report() {
    local logfile="$1"
    
    echo "=========================================="
    echo "Build Error Analysis Report"
    echo "=========================================="
    echo ""
    echo "Log file: $logfile"
    echo "Timestamp: $(stat -c %y "$logfile" 2>/dev/null || stat -f "%Sm" "$logfile")"
    echo ""
    
    echo "----------------------------------------"
    echo "Detected Error Types:"
    echo "----------------------------------------"
    
    local error_types
    mapfile -t error_types < <(detect_error_type "$logfile")
    
    if [[ ${#error_types[@]} -eq 0 ]]; then
        echo "No specific error patterns detected."
    else
        for error_type in "${error_types[@]}"; do
            echo ""
            echo "[$error_type]"
            echo "  Pattern: ${ERROR_PATTERNS[$error_type]}"
            echo "  Suggestion: ${ERROR_FIXES[$error_type]}"
        done
    fi
    
    echo ""
    echo "----------------------------------------"
    echo "Missing Packages Detected:"
    echo "----------------------------------------"
    
    local missing
    mapfile -t missing < <(extract_missing_packages "$logfile")
    
    if [[ ${#missing[@]} -eq 0 ]]; then
        echo "No missing packages detected."
    else
        for pkg in "${missing[@]}"; do
            local lib32_pkg
            lib32_pkg=$(suggest_lib32_package "$pkg")
            echo "  - $pkg (try: $lib32_pkg)"
        done
    fi
    
    if [[ $VERBOSE -eq 1 ]]; then
        echo ""
        echo "----------------------------------------"
        echo "Relevant Log Lines:"
        echo "----------------------------------------"
        grep -iE "error:|fatal:|failed|cannot find|undefined reference" "$logfile" | head -30
    fi
    
    echo ""
    echo "----------------------------------------"
    echo "Suggested Actions:"
    echo "----------------------------------------"
    
    if [[ " ${error_types[*]} " =~ " objcopy_error " ]]; then
        echo "1. Apply objcopy workaround patch to PKGBUILD:"
        echo "   Add to build():"
        echo "   find . -name '*.o' -exec objcopy --add-gnu-debuglink={} {} \\;"
        echo ""
    fi
    
    if [[ " ${error_types[*]} " =~ " missing_dep " ]] || [[ " ${error_types[*]} " =~ " pkg_config " ]]; then
        echo "2. Install missing dependencies:"
        mapfile -t missing < <(extract_missing_packages "$logfile")
        for pkg in "${missing[@]}"; do
            local lib32_pkg
            lib32_pkg=$(suggest_lib32_package "$pkg")
            echo "   sudo pacman -S $lib32_pkg"
        done
        echo ""
    fi
    
    echo "3. Re-run build after addressing the above issues."
}

attempt_fix() {
    local logfile="$1"
    
    log_info "Analyzing errors for potential automatic fixes..."
    
    local error_types
    mapfile -t error_types < <(detect_error_type "$logfile")
    
    local fix_applied=0
    
    if [[ " ${error_types[*]} " =~ " objcopy_error " ]]; then
        log_info "Detected objcopy error - this requires manual PKGBUILD patch"
        log_info "Apply the following to your PKGBUILD build() function:"
        echo ""
        echo "  # Workaround for objcopy issues with lib32 builds"
        echo "  find \"\$pkgdir\" -name '*.o' -exec sh -c 'objcopy --add-gnu-debuglink=\"\$1\" \"\$1\"' _ {} \\;"
        echo ""
        fix_applied=1
    fi
    
    if [[ " ${error_types[*]} " =~ " missing_dep " ]]; then
        log_info "Detected missing dependencies"
        
        local missing
        mapfile -t missing < <(extract_missing_packages "$logfile")
        
        if [[ ${#missing[@]} -gt 0 ]]; then
            local install_cmd="sudo pacman -S --needed"
            local aur_pkgs=()
            
            for pkg in "${missing[@]}"; do
                local lib32_pkg
                lib32_pkg=$(suggest_lib32_package "$pkg")
                
                if pacman -Si "$lib32_pkg" &>/dev/null; then
                    install_cmd+=" $lib32_pkg"
                else
                    aur_pkgs+=("$lib32_pkg")
                fi
            done
            
            echo ""
            log_info "Run the following to install missing dependencies:"
            echo ""
            
            if [[ "$install_cmd" != "sudo pacman -S --needed" ]]; then
                echo "$install_cmd"
            fi
            
            if [[ ${#aur_pkgs[@]} -gt 0 ]]; then
                echo ""
                echo "# AUR packages needed:"
                for pkg in "${aur_pkgs[@]}"; do
                    echo "yay -S $pkg"
                done
            fi
        fi
        fix_applied=1
    fi
    
    if [[ $fix_applied -eq 0 ]]; then
        log_warn "No automatic fixes available for detected error types"
        log_info "Run with -r for a detailed report"
    fi
}

main() {
    parse_args "$@"
    
    if [[ -z "$LOG_FILE" ]]; then
        LOG_FILE=$(find_latest_log) || exit 1
        log_info "Using latest log: $LOG_FILE"
    fi
    
    if [[ ! -f "$LOG_FILE" ]]; then
        log_error "Log file not found: $LOG_FILE"
        exit 1
    fi
    
    if [[ $FIX_MODE -eq 1 ]] && [[ $REPORT_MODE -eq 1 ]]; then
        generate_report "$LOG_FILE"
        echo ""
        attempt_fix "$LOG_FILE"
    elif [[ $REPORT_MODE -eq 1 ]]; then
        generate_report "$LOG_FILE"
    elif [[ $FIX_MODE -eq 1 ]]; then
        attempt_fix "$LOG_FILE"
    else
        log_info "Error types detected:"
        local error_types
        mapfile -t error_types < <(detect_error_type "$LOG_FILE")
        
        if [[ ${#error_types[@]} -eq 0 ]]; then
            log_warn "No specific error patterns detected"
            log_info "Run with -r for detailed report"
        else
            for error_type in "${error_types[@]}"; do
                echo "  - $error_type: ${ERROR_FIXES[$error_type]}"
            done
        fi
    fi
}

main "$@"
