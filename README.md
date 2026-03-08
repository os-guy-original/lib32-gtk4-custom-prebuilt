# lib32-gtk4-custom-prebuilt

> ⚠️ **AI MANAGEMENT TEST REPOSITORY**
> 
> This repository is a test to see how AI can manage a package repository, detect build errors, and handle patches for dependencies that fail to build. The AI agent "Kilo" manages this repository autonomously within defined safety limits.
> 
> See `Kilo.config.json` for the AI's permissions and scope.

A custom build system for `lib32-gtk4` and its problematic AUR dependencies on Arch Linux.

## Purpose

This repository provides prebuilt packages and build automation for `lib32-gtk4`, addressing common issues with AUR dependencies that often fail to compile or have broken dependency chains. The project aims to:

- Provide working builds of lib32-gtk4 for 32-bit application support
- Resolve AUR dependency compilation failures with patches
- Automate the build process for CI/CD integration
- Maintain a reproducible build environment

## AI Test Purpose

This repository serves as a testbed for AI-driven package management capabilities:

- **AI Package Management**: Tests how AI can autonomously manage a package repository
- **Error Detection**: The AI detects compilation errors in AUR dependencies by analyzing build logs
- **Patch Creation**: When build failures are detected, the AI creates and applies patches to fix issues
- **Pipeline Management**: The AI manages the entire build pipeline from dependency resolution to package creation
- **Safety Limits**: All AI operations are bounded by restrictions defined in `Kilo.config.json`

## Features

- **Automatic Dependency Resolution**: Identifies and builds all required AUR dependencies in the correct order
- **Compilation Error Detection**: Detects common compilation errors and applies known fixes automatically
- **Patched Builds**: Includes patches for known issues in upstream AUR packages
- **CI/CD Integration**: GitHub Actions workflow for automated package builds
- **Prebuilt Packages**: Binary packages available as releases for easy installation

## Usage

### Local Build

1. Clone the repository:
   ```bash
   git clone https://github.com/os-guy-original/lib32-gtk4-custom-prebuilt.git
   cd lib32-gtk4-custom-prebuilt
   ```

2. Install build dependencies:
   ```bash
   sudo pacman -S --needed base-devel multilib-devel
   ```

3. Run the build script:
   ```bash
   ./scripts/build-all.sh
   ```

4. Install built packages:
   ```bash
   sudo pacman -U packages/*.pkg.tar.zst
   ```

### Building Individual Packages

To build a specific package:

```bash
cd packages/dependencies/<package-name>
makepkg -si
```

### CI/CD Build

The repository includes GitHub Actions workflows that automatically build packages on push and pull requests. Built packages are uploaded as artifacts and can be downloaded from the Actions tab.

## Dependencies

The following AUR packages are required dependencies that this repository builds:

### Core Dependencies

| Package | Description | AUR Status |
|---------|-------------|------------|
| `lib32-gtk4` | GTK4 library (32-bit) | Requires multilib dependencies |
| `lib32-graphene` | Thin layer of graphic data types (32-bit) | Build issues common |
| `lib32-glib2` | GLib library (32-bit) | From multilib repo |
| `lib32-pcre2` | Perl Compatible Regular Expressions (32-bit) | From multilib repo |
| `lib32-libffi` | Foreign Function Interface library (32-bit) | From multilib repo |

### Build Dependencies

| Package | Description | Purpose |
|---------|-------------|---------|
| `gtk4` | GTK4 library | Build dependency |
| `glib2` | GLib library | Build dependency |
| `graphene` | Graphics data types library | Build dependency |
| `meson` | Build system | Required for compilation |
| `ninja` | Build tool | Required for meson |

## Build Order

Due to dependency chains, packages must be built in a specific order:

```
1. lib32-libffi (if not in multilib)
2. lib32-pcre2 (if not in multilib)
3. lib32-glib2 (if not in multilib)
4. lib32-graphene
5. lib32-gtk4
```

### Dependency Graph

```
lib32-gtk4
    └── lib32-graphene
            └── lib32-glib2
                    ├── lib32-pcre2
                    └── lib32-libffi
```

## Directory Structure

```
lib32-gtk4-custom-prebuilt/
├── README.md                 # This file
├── .gitignore               # Git ignore patterns
├── packages/                # Package build files
│   ├── README.md
│   ├── lib32-gtk4/          # Main package
│   │   ├── PKGBUILD
│   │   └── patches/
│   └── dependencies/        # AUR dependencies with patches
│       ├── lib32-graphene/
│       └── ...
├── scripts/                 # Build and utility scripts
│   ├── README.md
│   ├── build-all.sh         # Build all packages
│   ├── resolve-deps.sh      # Dependency resolver
│   └── detect-errors.sh     # Error detection utility
├── .github/                 # GitHub Actions workflows
│   └── workflows/
│       └── build.yml
└── releases/                # Prebuilt packages (generated)
```

## Known Issues and Fixes

### lib32-graphene

- **Issue**: Missing `gobject-introspection` support in 32-bit builds
- **Fix**: Disable introspection in PKGBUILD

### lib32-gtk4

- **Issue**: Vulkan support causes build failures on some systems
- **Fix**: Optional Vulkan dependency with fallback

## AI Configuration (Kilo.config.json)

The `Kilo.config.json` file defines the AI agent's operational parameters:

### Permissions
- Create, modify, and delete files within this repository
- Execute build scripts and run tests
- Create git commits with descriptive messages
- Create and respond to GitHub issues and pull requests

### Safety Restrictions
- **Repository Scope**: AI operations are limited to this repository only
- **No External Access**: Cannot access or modify system files outside the repo
- **No Secret Exposure**: Cannot read or write secrets/credentials
- **No Destructive Git Operations**: Cannot force push or perform hard resets without explicit approval
- **Commit Limits**: Cannot amend commits that have been pushed to remote

### Operational Limits
- Maximum file size restrictions apply
- Build timeouts prevent runaway processes
- Network access limited to package repositories and GitHub API

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

This project packages software from various sources. Each package retains its original license. See individual PKGBUILD files for license information.

## Disclaimer

This project is not affiliated with Arch Linux or the GTK project. Use at your own risk. Always verify PKGBUILD files before building.
