# lib32-gtk4 Dependency Packages

This directory contains PKGBUILD files for all 32-bit dependencies required to build lib32-gtk4.

## Package Sources

### From AUR (Modified)

These packages are sourced from the Arch User Repository with modifications for cross-compilation:

| Package | AUR Source | Modifications |
|---------|-----------|---------------|
| `lib32-graphene` | [aur/lib32-graphene](https://aur.archlinux.org/packages/lib32-graphene) | Disabled tests, disabled introspection |
| `lib32-libcloudproviders` | [aur/lib32-libcloudproviders](https://aur.archlinux.org/packages/lib32-libcloudproviders) | Cross-compilation setup, disabled introspection |
| `lib32-tinysparql` | [aur/lib32-tinysparql](https://aur.archlinux.org/packages/lib32-tinysparql) | Disabled tests/docs, cross-compilation setup |
| `lib32-libstemmer` | [aur/lib32-libstemmer](https://aur.archlinux.org/packages/lib32-libstemmer) | Includes shared library patch |
| `lib32-avahi` | [aur/lib32-avahi](https://aur.archlinux.org/packages/lib32-avahi) | Includes installation fixes patch |

### Created from Scratch

| Package | Purpose | Notes |
|---------|---------|-------|
| `lib32-gst-plugins-bad-libs` | GStreamer bad plugin libraries | Libraries only, no plugins. Required for GTK4 media support. |

## Dependency Tree

```
lib32-gtk4
├── lib32-graphene
├── lib32-libcloudproviders
├── lib32-gst-plugins-bad-libs
│   └── lib32-gst-plugins-base-libs (from extra)
│       └── lib32-gstreamer (from extra)
└── lib32-tinysparql (formerly tracker3)
    ├── lib32-avahi
    ├── lib32-json-glib (from AUR)
    ├── lib32-libsoup3 (from AUR)
    ├── lib32-libstemmer
    └── lib32-icu (from extra)
```

## Patches Applied

### lib32-libstemmer
- `0001-Make-libstemmer-a-shared-library.patch`: Converts static library to shared library for 32-bit builds

### lib32-avahi
- `0001-HACK-Install-fixes.patch`: Fixes installation issues including moving example services to docs and header symlink compatibility

## Build Order

Dependencies should be built in the following order to satisfy dependencies:

1. `lib32-libstemmer`
2. `lib32-avahi`
3. `lib32-graphene`
4. `lib32-libcloudproviders`
5. `lib32-gst-plugins-bad-libs`
6. `lib32-tinysparql` (requires all above)

## Cross-Compilation Notes

All packages use one of these cross-compilation methods:

1. **GCC flags method**: Setting `CC='gcc -m32'` and `PKG_CONFIG='/usr/bin/i686-pc-linux-gnu-pkg-config'`
2. **Meson cross-file**: Using `--cross-file lib32` with appropriate environment variables

The meson cross-file method requires a cross file at `/usr/share/meson/cross/lib32.ini` or similar location.

## Version Compatibility

- GStreamer packages: 1.24.x series
- GNOME packages: Match current Arch Linux versions
- tinysparql: 3.9.x (provides tracker3 compatibility)

## Testing

After building, verify packages with:
```bash
namcap <package>.pkg.tar.zst
```

And check library dependencies with:
```bash
ldd /usr/lib32/lib<name>.so
```
