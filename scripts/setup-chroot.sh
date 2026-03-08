#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

CHROOT_ROOT="/var/lib/archbuild/lib32-gtk4"
ACTION=""

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Manage Arch build chroot for clean lib32-gtk4 builds.

Options:
    -h          Show this help message
    -c          Create new chroot
    -u          Update existing chroot
    -d          Destroy chroot

The chroot is created at: $CHROOT_ROOT

This provides a clean build environment with:
    - base-devel and multilib-devel packages
    - Properly configured pacman with multilib enabled

Examples:
    $(basename "$0") -c          Create new chroot
    $(basename "$0") -u          Update existing chroot
    $(basename "$0") -d          Destroy chroot
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h) show_help; exit 0 ;;
            -c) ACTION="create" ;;
            -u) ACTION="update" ;;
            -d) ACTION="destroy" ;;
            *) log_error "Unknown option: $1"; show_help; exit 1 ;;
        esac
        shift
    done
}

check_sudo() {
    if [[ $EUID -ne 0 ]]; then
        if ! sudo -n true 2>/dev/null; then
            log_error "This script requires sudo access"
            exit 1
        fi
    fi
}

check_existing_chroot() {
    if [[ -d "$CHROOT_ROOT" ]]; then
        return 0
    fi
    return 1
}

install_packages() {
    log_info "Installing base packages..."
    sudo pacstrap -c "$CHROOT_ROOT" base base-devel multilib-devel
    
    log_info "Installing additional build dependencies..."
    local packages=(
        git
        meson
        ninja
        cmake
        pkgconf
        autoconf
        automake
        libtool
    )
    
    sudo pacstrap -c "$CHROOT_ROOT" "${packages[@]}"
}

configure_pacman() {
    log_info "Configuring pacman..."
    
    sudo mkdir -p "$CHROOT_ROOT/etc"
    
    sudo tee "$CHROOT_ROOT/etc/pacman.conf" > /dev/null << 'EOF'
[options]
HoldPkg     = pacman glibc
Architecture = auto
CheckSpace
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
    
    if [[ -f /etc/pacman.d/mirrorlist ]]; then
        sudo cp /etc/pacman.d/mirrorlist "$CHROOT_ROOT/etc/pacman.d/mirrorlist"
    else
        log_warn "Mirrorlist not found, you may need to configure mirrors manually"
    fi
}

configure_makepkg() {
    log_info "Configuring makepkg..."
    
    sudo sed -i 's/#MAKEFLAGS="-j2"/MAKEFLAGS="-j$(nproc)"/' "$CHROOT_ROOT/etc/makepkg.conf"
    sudo sed -i 's/PKGEXT=.pkg.tar.gz/PKGEXT=.pkg.tar.zst/' "$CHROOT_ROOT/etc/makepkg.conf"
    sudo sed -i 's/COMPRESSZST=(zstd -c -T0 -18 -)/COMPRESSZST=(zstd -c -T0 -15 -)/' "$CHROOT_ROOT/etc/makepkg.conf"
}

configure_sudo() {
    log_info "Configuring sudo for build user..."
    
    sudo tee -a "$CHROOT_ROOT/etc/sudoers" > /dev/null << 'EOF'
builduser ALL=(ALL) NOPASSWD: ALL
EOF
}

create_build_user() {
    log_info "Creating build user..."
    
    sudo chroot "$CHROOT_ROOT" /bin/bash -c '
        if ! id builduser &>/dev/null; then
            useradd -m -G wheel -s /bin/bash builduser
        fi
    '
}

create_chroot() {
    log_info "Creating chroot at $CHROOT_ROOT..."
    
    if check_existing_chroot; then
        log_warn "Chroot already exists at $CHROOT_ROOT"
        read -p "Remove existing chroot and recreate? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            destroy_chroot
        else
            log_error "Aborted"
            exit 1
        fi
    fi
    
    sudo mkdir -p "$CHROOT_ROOT"
    
    install_packages
    configure_pacman
    configure_makepkg
    create_build_user
    configure_sudo
    
    log_success "Chroot created successfully at $CHROOT_ROOT"
    log_info "To use the chroot for building:"
    echo "  sudo chroot $CHROOT_ROOT /bin/bash"
    echo "  su - builduser"
}

update_chroot() {
    log_info "Updating chroot..."
    
    if ! check_existing_chroot; then
        log_error "Chroot not found at $CHROOT_ROOT"
        log_info "Run with -c to create a new chroot"
        exit 1
    fi
    
    log_info "Running pacman -Syu in chroot..."
    sudo chroot "$CHROOT_ROOT" /bin/bash -c 'pacman -Syu --noconfirm'
    
    log_success "Chroot updated successfully"
}

destroy_chroot() {
    log_info "Destroying chroot at $CHROOT_ROOT..."
    
    if ! check_existing_chroot; then
        log_warn "Chroot not found at $CHROOT_ROOT"
        return 0
    fi
    
    sudo rm -rf "$CHROOT_ROOT"
    
    log_success "Chroot destroyed successfully"
}

enter_chroot() {
    log_info "Entering chroot..."
    
    if ! check_existing_chroot; then
        log_error "Chroot not found at $CHROOT_ROOT"
        exit 1
    fi
    
    sudo chroot "$CHROOT_ROOT" /bin/bash
}

main() {
    parse_args "$@"
    
    if [[ -z "$ACTION" ]]; then
        show_help
        exit 0
    fi
    
    check_sudo
    
    case "$ACTION" in
        create)
            create_chroot
            ;;
        update)
            update_chroot
            ;;
        destroy)
            destroy_chroot
            ;;
    esac
}

main "$@"
