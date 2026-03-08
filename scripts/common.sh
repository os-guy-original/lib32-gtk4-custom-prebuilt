#!/bin/bash
# Common functions and config reader for lib32-prebuilts

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/packages.conf"
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

# Parse packages.conf and return package info
# Usage: get_packages [--format json|simple]
get_packages() {
    local format="${1:-simple}"
    
    [ ! -f "$CONFIG_FILE" ] && { error "packages.conf not found"; return 1; }
    
    while IFS='|' read -r name version depends notes || [ -n "$name" ]; do
        # Skip comments and empty lines
        [[ -z "$name" || "$name" =~ ^# ]] && continue
        
        case "$format" in
            simple)
                echo "$name|$version|$depends"
                ;;
            json)
                echo "{\"name\":\"$name\",\"version\":\"$version\",\"depends\":\"$depends\"}"
                ;;
        esac
    done < "$CONFIG_FILE"
}

# Get a single package's info
# Usage: get_package_info <package_name>
get_package_info() {
    local pkgname="$1"
    
    while IFS='|' read -r name version depends notes; do
        [[ "$name" == "$pkgname" ]] && {
            echo "$name|$version|$depends|$notes"
            return 0
        }
    done < "$CONFIG_FILE"
    return 1
}

# Resolve build order based on dependencies
# Returns packages in dependency order
get_build_order() {
    local packages=()
    local built=()
    
    # Read all packages
    while IFS='|' read -r name version depends notes; do
        [[ -z "$name" || "$name" =~ ^# ]] && continue
        packages+=("$name|$version|$depends")
    done < "$CONFIG_FILE"
    
    # Simple topological sort - packages with no lib32 dependencies first
    local changed=1
    local iterations=0
    local max_iterations=${#packages[@]}
    
    while [ $changed -eq 1 ] && [ $iterations -lt $max_iterations ]; do
        changed=0
        iterations=$((iterations + 1))
        
        for pkg in "${packages[@]}"; do
            IFS='|' read -r name version depends <<< "$pkg"
            
            # Skip if already in build order
            [[ " ${built[*]} " =~ " $name " ]] && continue
            
            # Check if all lib32 dependencies are satisfied
            local deps_met=1
            for dep in ${depends//,/ }; do
                # Only check lib32- dependencies that are in our packages
                if [[ "$dep" =~ ^lib32- ]] && [[ ! " ${built[*]} " =~ " $dep " ]]; then
                    # Check if this dep is one of our packages
                    local found=0
                    for p in "${packages[@]}"; do
                        [[ "$p" =~ ^$dep\| ]] && { found=1; break; }
                    done
                    [ $found -eq 1 ] && deps_met=0
                fi
            done
            
            if [ $deps_met -eq 1 ]; then
                built+=("$name")
                changed=1
            fi
        done
    done
    
    printf '%s\n' "${built[@]}"
}

# Find package directory
# Usage: find_pkgdir <package_name>
find_pkgdir() {
    local pkgname="$1"
    
    for dir in "$PROJECT_ROOT/packages/$pkgname" "$PROJECT_ROOT/packages/dependencies/$pkgname"; do
        [ -d "$dir" ] && { echo "$dir"; return 0; }
    done
    return 1
}

# Check if package is already built and valid
# Usage: check_package_valid <package_name> <version>
check_package_valid() {
    local pkgname="$1"
    local pkgver="$2"
    local pkgdir
    
    pkgdir=$(find_pkgdir "$pkgname") || return 1
    [ ! -f "$pkgdir/PKGBUILD" ] && return 1
    
    # Get epoch from PKGBUILD
    local epoch=""
    source "$pkgdir/PKGBUILD" epoch 2>/dev/null || true
    local fullver="${epoch:+$epoch:}$pkgver"
    
    # Check package file
    local pkgfile=$(ls "$REPO_DIR/${pkgname}-${fullver}"*-x86_64.pkg.tar.zst 2>/dev/null | grep -v debug | head -1)
    [ -z "$pkgfile" ] && return 1
    
    # Check signature
    [ ! -f "${pkgfile}.sig" ] && return 1
    
    # Verify signature
    gpg --verify "${pkgfile}.sig" "$pkgfile" 2>/dev/null || return 1
    
    return 0
}

# Export functions for use in other scripts
export -f info ok warn error step
export -f get_packages get_package_info get_build_order find_pkgdir check_package_valid
