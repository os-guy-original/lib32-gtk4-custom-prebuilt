#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

CHECK_INSTALLED=0
OUTPUT_GRAPH=0
LIST_DEPS=0
MISSING_DEPS=0
INSTALL_COMMANDS=0

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Dependency resolver for lib32-gtk4 build.

Options:
    -h          Show this help message
    -c          Check which packages are already installed
    -g          Output dependency graph in DOT format
    -l          List all packages with their dependencies
    -m          List missing dependencies
    -i          Generate install commands for missing dependencies

Examples:
    $(basename "$0") -c          Check installed status
    $(basename "$0") -g | dot -Tpng > deps.png   Generate graph
    $(basename "$0") -m          Show missing dependencies
    $(basename "$0") -i          Show install commands
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h) show_help; exit 0 ;;
            -c) CHECK_INSTALLED=1 ;;
            -g) OUTPUT_GRAPH=1 ;;
            -l) LIST_DEPS=1 ;;
            -m) MISSING_DEPS=1 ;;
            -i) INSTALL_COMMANDS=1 ;;
            *) log_error "Unknown option: $1"; show_help; exit 1 ;;
        esac
        shift
    done
}

declare -A PACKAGE_DEPS
declare -A PACKAGE_VERSIONS
declare -A PACKAGE_AUR_URLS
declare -A PACKAGE_BUILD_OPTS

parse_dependencies_conf() {
    local deps_file="$SCRIPT_DIR/dependencies.conf"
    
    if [[ ! -f "$deps_file" ]]; then
        log_error "Dependencies file not found: $deps_file"
        exit 1
    fi
    
    while IFS='|' read -r name version depends aur_url build_opts issues || [[ -n "$name" ]]; do
        [[ -z "$name" ]] && continue
        [[ "$name" =~ ^# ]] && continue
        
        name=$(echo "$name" | tr -d ' ')
        PACKAGE_VERSIONS["$name"]="$version"
        PACKAGE_DEPS["$name"]="$depends"
        PACKAGE_AUR_URLS["$name"]="$aur_url"
        PACKAGE_BUILD_OPTS["$name"]="$build_opts"
    done < <(cat "$deps_file")
}

is_package_installed() {
    local pkg="$1"
    pacman -Qi "$pkg" &> /dev/null
}

check_installed() {
    parse_dependencies_conf
    
    printf "%-30s %-15s %s\n" "Package" "Version" "Status"
    printf "%-30s %-15s %s\n" "-------" "-------" "------"
    
    for pkg in "${!PACKAGE_VERSIONS[@]}"; do
        local status
        if is_package_installed "$pkg"; then
            status="${GREEN}Installed${NC}"
        else
            status="${RED}Not Installed${NC}"
        fi
        printf "%-30s %-15s %b\n" "$pkg" "${PACKAGE_VERSIONS[$pkg]}" "$status"
    done | sort
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
        
        local deps="${PACKAGE_DEPS[$pkg]:-}"
        
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

output_dot_graph() {
    parse_dependencies_conf
    
    echo "digraph dependencies {"
    echo "    rankdir=BT;"
    echo "    node [shape=box];"
    echo ""
    
    for pkg in "${!PACKAGE_DEPS[@]}"; do
        local deps="${PACKAGE_DEPS[$pkg]}"
        if [[ -n "$deps" ]]; then
            IFS=',' read -ra dep_array <<< "$deps"
            for dep in "${dep_array[@]}"; do
                dep=$(echo "$dep" | tr -d ' ')
                [[ -z "$dep" ]] && continue
                echo "    \"$pkg\" -> \"$dep\";"
            done
        fi
    done
    
    echo ""
    for pkg in "${!PACKAGE_VERSIONS[@]}"; do
        local label="$pkg\\n${PACKAGE_VERSIONS[$pkg]}"
        if is_package_installed "$pkg"; then
            echo "    \"$pkg\" [label=\"$label\", style=filled, fillcolor=lightgreen];"
        else
            echo "    \"$pkg\" [label=\"$label\", style=filled, fillcolor=lightcoral];"
        fi
    done
    
    echo "}"
}

list_dependencies() {
    parse_dependencies_conf
    
    local packages
    mapfile -t packages < <(echo "${!PACKAGE_DEPS[@]}" | tr ' ' '\n' | sort)
    mapfile -t packages < <(topological_sort "${packages[@]}")
    
    printf "%-30s %-15s %s\n" "Package" "Version" "Dependencies"
    printf "%-30s %-15s %s\n" "-------" "-------" "------------"
    
    for pkg in "${packages[@]}"; do
        printf "%-30s %-15s %s\n" "$pkg" "${PACKAGE_VERSIONS[$pkg]}" "${PACKAGE_DEPS[$pkg]:-none}"
    done
}

list_missing() {
    parse_dependencies_conf
    
    local missing=()
    
    for pkg in "${!PACKAGE_VERSIONS[@]}"; do
        if ! is_package_installed "$pkg"; then
            missing+=("$pkg")
        fi
        
        local deps="${PACKAGE_DEPS[$pkg]}"
        if [[ -n "$deps" ]]; then
            IFS=',' read -ra dep_array <<< "$deps"
            for dep in "${dep_array[@]}"; do
                dep=$(echo "$dep" | tr -d ' ')
                [[ -z "$dep" ]] && continue
                if ! is_package_installed "$dep"; then
                    missing+=("$dep")
                fi
            done
        fi
    done
    
    missing=($(printf '%s\n' "${missing[@]}" | sort -u))
    
    if [[ ${#missing[@]} -eq 0 ]]; then
        log_success "All dependencies are installed"
        return 0
    fi
    
    log_warn "Missing dependencies (${#missing[@]}):"
    for pkg in "${missing[@]}"; do
        echo "  - $pkg"
    done
}

generate_install_commands() {
    parse_dependencies_conf
    
    local missing=()
    
    for pkg in "${!PACKAGE_VERSIONS[@]}"; do
        if ! is_package_installed "$pkg"; then
            missing+=("$pkg")
        fi
        
        local deps="${PACKAGE_DEPS[$pkg]}"
        if [[ -n "$deps" ]]; then
            IFS=',' read -ra dep_array <<< "$deps"
            for dep in "${dep_array[@]}"; do
                dep=$(echo "$dep" | tr -d ' ')
                [[ -z "$dep" ]] && continue
                if ! is_package_installed "$dep"; then
                    missing+=("$dep")
                fi
            done
        fi
    done
    
    missing=($(printf '%s\n' "${missing[@]}" | sort -u))
    
    if [[ ${#missing[@]} -eq 0 ]]; then
        log_success "All dependencies are installed"
        return 0
    fi
    
    local pacman_pkgs=()
    local aur_pkgs=()
    
    for pkg in "${missing[@]}"; do
        if [[ "$pkg" == lib32-* ]]; then
            aur_pkgs+=("$pkg")
        elif pacman -Si "$pkg" &> /dev/null; then
            pacman_pkgs+=("$pkg")
        else
            aur_pkgs+=("$pkg")
        fi
    done
    
    if [[ ${#pacman_pkgs[@]} -gt 0 ]]; then
        echo "# Install from official repos:"
        echo "sudo pacman -S ${pacman_pkgs[*]}"
        echo ""
    fi
    
    if [[ ${#aur_pkgs[@]} -gt 0 ]]; then
        echo "# Install from AUR:"
        for pkg in "${aur_pkgs[@]}"; do
            if [[ -n "${PACKAGE_AUR_URLS[$pkg]:-}" ]]; then
                echo "# $pkg: ${PACKAGE_AUR_URLS[$pkg]}"
            else
                echo "# $pkg: https://aur.archlinux.org/packages/$pkg"
            fi
        done
        echo ""
        echo "yay -S ${aur_pkgs[*]}"
    fi
}

main() {
    parse_args "$@"
    
    local action_count=$((CHECK_INSTALLED + OUTPUT_GRAPH + LIST_DEPS + MISSING_DEPS + INSTALL_COMMANDS))
    
    if [[ $action_count -eq 0 ]]; then
        show_help
        exit 0
    fi
    
    if [[ $CHECK_INSTALLED -eq 1 ]]; then
        check_installed
    elif [[ $OUTPUT_GRAPH -eq 1 ]]; then
        output_dot_graph
    elif [[ $LIST_DEPS -eq 1 ]]; then
        list_dependencies
    elif [[ $MISSING_DEPS -eq 1 ]]; then
        list_missing
    elif [[ $INSTALL_COMMANDS -eq 1 ]]; then
        generate_install_commands
    fi
}

main "$@"
