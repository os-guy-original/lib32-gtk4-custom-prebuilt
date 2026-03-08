# Packages Directory

This directory contains all PKGBUILD files and related build artifacts for lib32-gtk4 and its dependencies.

## Structure

```
packages/
├── README.md                    # This file
├── lib32-gtk4/                  # Main package
│   ├── PKGBUILD                 # Package build definition
│   ├── patches/                 # Source patches
│   │   ├── fix-build.patch
│   │   └── disable-vulkan.patch
│   └── *.install                # Install scripts (if any)
└── dependencies/                # AUR dependencies with modifications
    ├── lib32-graphene/
    │   ├── PKGBUILD
    │   └── patches/
    ├── lib32-glib2/             # If custom build needed
    └── ...                      # Other dependencies
```

## Directory Descriptions

### `lib32-gtk4/`

The main GTK4 32-bit library package. This is the primary output of the build system.

**Contents:**
- `PKGBUILD` - Modified Arch Linux package build script
- `patches/` - Source patches for build fixes
- `*.install` - Post-installation hooks (if needed)

**Modifications from AUR:**
- Fixed dependency declarations
- Build configuration adjustments
- Optional feature toggles

### `dependencies/`

Contains AUR dependency packages that require modifications or patches to build successfully.

Each subdirectory follows the standard Arch Linux packaging format:

```
dependencies/<package-name>/
├── PKGBUILD           # Package definition
├── patches/           # Optional patches directory
│   ├── 0001-fix.patch
│   └── 0002-feature.patch
├── <package>.install  # Optional install script
└── <files>            # Additional files needed by PKGBUILD
```

## Package Guidelines

### PKGBUILD Standards

All PKGBUILD files follow the Arch Linux packaging standards with these additions:

1. Include a `# Maintainer` header with contact information
2. Document any modifications from upstream AUR in comments
3. Use `sha256sums` for integrity verification
4. Include `check()` function when tests are available

### Patch Naming Convention

Patches follow this naming scheme:

```
NNNN-description.patch
```

Where `NNNN` is a four-digit number indicating the order patches should be applied:

- `0001-` through `0099-` - Upstream backports
- `0100-` through `0199-` - Build system fixes
- `0200-` through `0299-` - Dependency fixes
- `0300-` through `0399-` - Feature modifications

### Version Control

Each package directory may contain a `.gitrev` file specifying the upstream git revision the package is based on:

```
a1b2c3d4
```

## Adding a New Package

1. Create directory: `mkdir -p packages/dependencies/<package-name>`

2. Copy upstream PKGBUILD from AUR

3. Apply necessary modifications

4. Create patches if needed

5. Update the dependency resolver script

6. Document changes in the package README

## Package-Specific Notes

### lib32-gtk4

- Requires `multilib` repository enabled
- May need `gobject-introspection` disabled for cross-compilation
- Vulkan support is optional and may cause issues on some systems

### lib32-graphene

- Uses Meson build system
- Requires `gtk-doc` disabled for 32-bit builds
- Introspection must be disabled

## Testing Packages

Before contributing, verify packages build correctly:

```bash
# In package directory
makepkg -sf

# Run tests (if available)
makepkg -sf --check
```

## Resources

- [Arch Linux Packaging Standards](https://wiki.archlinux.org/title/PKGBUILD)
- [makepkg Documentation](https://man.archlinux.org/man/makepkg.8)
- [Arch Build System](https://wiki.archlinux.org/title/Arch_Build_System)
