#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PACKAGES_DIR="$ROOT_DIR/packages"
OUTPUT_FILE="$ROOT_DIR/FEATURES.md"

get_pkgname() {
    local pkgbuild="$1"
    local pkgbuild_dir
    pkgbuild_dir=$(dirname "$pkgbuild")
    local pkgname
    pkgname=$(basename "$pkgbuild_dir")
    echo "$pkgname"
}

extract_meson_options() {
    local content="$1"
    local -a options=()
    
    local line
    while IFS= read -r line; do
        local matches
        matches=$(echo "$line" | grep -oE '\-D[[:space:]]?[a-zA-Z0-9_.-]+=[^[:space:]]+' || true)
        if [[ -n "$matches" ]]; then
            while IFS= read -r match; do
                [[ -z "$match" ]] && continue
                local opt val
                opt=$(echo "$match" | sed 's/-D[[:space:]]*\([^=]*\)=.*/\1/')
                val=$(echo "$match" | sed "s/-[^=]*=//" | tr -d "'\"")
                [[ "$opt" == "package-name" ]] && continue
                [[ "$opt" == "package-origin" ]] && continue
                options+=("$opt|$val|$match")
            done <<< "$matches"
        fi
    done <<< "$content"
    
    printf '%s\n' "${options[@]}"
}

extract_configure_options() {
    local content="$1"
    local -a options=()
    
    while IFS= read -r line; do
        if [[ "$line" =~ --enable-([a-zA-Z0-9_-]+) ]]; then
            local opt="${BASH_REMATCH[1]}"
            options+=("$opt|enabled|--enable-$opt")
        elif [[ "$line" =~ --disable-([a-zA-Z0-9_-]+) ]]; then
            local opt="${BASH_REMATCH[1]}"
            options+=("$opt|disabled|--disable-$opt")
        fi
    done <<< "$content"
    
    printf '%s\n' "${options[@]}"
}

extract_build_options() {
    local pkgbuild="$1"
    
    local build_start
    build_start=$(grep -n "^build()" "$pkgbuild" | head -1 | cut -d: -f1)
    
    if [[ -z "$build_start" ]]; then
        return 1
    fi
    
    local remaining_lines
    remaining_lines=$(tail -n +"$build_start" "$pkgbuild" | head -30)
    
    local -a all_options=()
    
    local meson_opts
    meson_opts=$(extract_meson_options "$remaining_lines")
    if [[ -n "$meson_opts" ]]; then
        while IFS='|' read -r opt val flag; do
            all_options+=("$opt|$val|$flag")
        done <<< "$meson_opts"
    fi
    
    local conf_opts
    conf_opts=$(extract_configure_options "$remaining_lines")
    if [[ -n "$conf_opts" ]]; then
        while IFS='|' read -r opt val flag; do
            all_options+=("$opt|$val|$flag")
        done <<< "$conf_opts"
    fi
    
    if [[ ${#all_options[@]} -gt 0 ]]; then
        printf '%s\n' "${all_options[@]}"
    fi
}

generate_package_section() {
    local pkgname="$1"
    local pkgbuild="$2"
    
    echo "## $pkgname"
    echo ""
    echo "| Feature | Status | Build Flag |"
    echo "|---------|--------|------------|"
    
    local -A seen
    local has_options=0
    
    while IFS='|' read -r opt val flag; do
        [[ -z "$opt" ]] && continue
        [[ "${seen[$opt]:-}" == "1" ]] && continue
        seen[$opt]=1
        has_options=1
        echo "| $opt | $val | $flag |"
    done < <(extract_build_options "$pkgbuild")
    
    if [[ $has_options -eq 0 ]]; then
        echo "| (none detected) | - | - |"
    fi
    
    echo ""
}

main() {
    echo "# Feature Detection Report"
    echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo "This report shows build options extracted from PKGBUILD files in the packages/ directory."
    echo ""
    
    local -a pkgbuilds
    mapfile -t pkgbuilds < <(find "$PACKAGES_DIR" -name "PKGBUILD" -type f 2>/dev/null | sort)
    
    if [[ ${#pkgbuilds[@]} -eq 0 ]]; then
        echo "No PKGBUILD files found in $PACKAGES_DIR"
        exit 1
    fi
    
    for pkgbuild in "${pkgbuilds[@]}"; do
        local pkgname
        pkgname=$(get_pkgname "$pkgbuild")
        generate_package_section "$pkgname" "$pkgbuild"
    done
}

main "$@"
