#!/bin/bash
# Common functions for lib32-prebuilts

# Use PWD when sourced, or script dir when executed directly
if [[ -n "${BASH_SOURCE[0]}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    SCRIPT_DIR="$(pwd)/scripts"
fi

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

get_packages() {
    [ ! -f "$CONFIG_FILE" ] && return 1
    while IFS='|' read -r name version depends notes; do
        [[ -z "$name" || "$name" =~ ^# ]] && continue
        echo "$name|$version|$depends"
    done < "$CONFIG_FILE"
}

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

get_build_order() {
    local -A pkg_deps
    local -a pkg_names
    local -a order
    local changed=1
    local iterations=0
    
    while IFS='|' read -r name version depends notes; do
        [[ -z "$name" || "$name" =~ ^# ]] && continue
        pkg_names+=("$name")
        pkg_deps["$name"]="$depends"
    done < "$CONFIG_FILE"
    
    while [ $changed -eq 1 ] && [ $iterations -lt 50 ]; do
        changed=0
        iterations=$((iterations + 1))
        
        for name in "${pkg_names[@]}"; do
            [[ " ${order[*]} " =~ " $name " ]] && continue
            local deps="${pkg_deps[$name]}"
            local satisfied=1
            
            for dep in ${deps//,/ }; do
                if [[ "$dep" =~ ^lib32- ]]; then
                    local found=0
                    for p in "${pkg_names[@]}"; do
                        [[ "$p" == "$dep" ]] && found=1
                    done
                    if [ $found -eq 1 ] && [[ ! " ${order[*]} " =~ " $dep " ]]; then
                        satisfied=0
                        break
                    fi
                fi
            done
            
            if [ $satisfied -eq 1 ]; then
                order+=("$name")
                changed=1
            fi
        done
    done
    
    printf '%s\n' "${order[@]}"
}

find_pkgdir() {
    local pkgname="$1"
    for dir in "$PROJECT_ROOT/packages/$pkgname" "$PROJECT_ROOT/packages/dependencies/$pkgname"; do
        [ -d "$dir" ] && { echo "$dir"; return 0; }
    done
    return 1
}

check_package_valid() {
    local pkgname="$1"
    local pkgver="$2"
    
    # Use ls with full path
    local pkgfile=$(ls "$REPO_DIR/${pkgname}-${pkgver}"*-x86_64.pkg.tar.zst 2>/dev/null | grep -v debug | head -1)
    
    if [ -z "$pkgfile" ]; then
        return 1
    fi
    
    if [ ! -f "${pkgfile}.sig" ]; then
        return 1
    fi
    
    return 0
}
