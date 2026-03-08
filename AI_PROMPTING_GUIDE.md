# AI Prompting Guide for lib32-gtk4-custom-prebuilt

This document serves as a comprehensive guide for AI assistants tasked with working on this repository. It provides essential context, history, and operational procedures to ensure continuity and effective problem-solving.

## 1. Repository Purpose

This repository exists as an AI management test project focused on building `lib32-gtk4` on Arch Linux. The primary objective is to create a working 32-bit GTK4 library stack for multilib usage on 64-bit Arch Linux systems. The original AUR (Arch User Repository) package contains several bugs that prevent proper compilation, including dependency issues where certain required packages do not compile correctly or have incomplete build configurations.

The repository serves dual purposes: first, to produce working 32-bit GTK4 packages that can be used in multilib environments, and second, to serve as a testing ground for AI-driven software engineering workflows. The build system was created entirely from scratch after identifying deficiencies in the upstream AUR packages.

## 2. What Has Been Done

The following represents the extensive work completed on this repository. This context is critical for any AI picking up this task, as it demonstrates the complexity of the build system and the iterative problem-solving process employed.

### 2.1 Build System Creation

The complete build system was created from scratch, establishing a reproducible workflow for building 32-bit packages on Arch Linux using GitHub Actions. This includes the primary workflow file at `.github/workflows/build.yml`, shell scripts for dependency resolution, building, and cleanup operations in the `scripts/` directory, and custom PKGBUILD files for all required dependencies.

### 2.2 Dependency Package Creation

Eight custom PKGBUILDs were created for dependencies that either did not exist in the AUR or required modifications:

- `lib32-gst-plugins-bad-libs` — Created from scratch because the AUR repository was empty. This is the most problematic package in the entire build chain.
- `lib32-avahi` — Modified with patches to fix installation issues.
- `lib32-libstemmer` — Converted from static library to shared library configuration.
- `lib32-tinysparql` — Created to satisfy GIO/GVfs dependencies.
- `lib32-libcloudproviders` — Created as a required dependency for GTK4.
- `lib32-graphene` — Created for 32-bit version required by GTK4.
- `lib32-gdbm` — Created as a runtime dependency.
- Additional dependency packages were systematically identified and added as the build progressed.

### 2.3 Bug Fixes and Corrections

The following significant fixes were applied during the build process:

- SHA256 checksums were corrected for multiple packages where upstream sources had changed.
- Approximately fifteen or more build errors were detected and resolved through iterative compilation and error analysis.
- Missing dependencies were identified and added to the workflow as they were encountered during compilation failures.
- The build process was structured to build packages incrementally, allowing each dependency to be validated before proceeding to dependent packages.

### 2.4 Meson Configuration Fixes

For `gst-plugins-bad-libs`, multiple problematic meson build options were disabled to prevent compilation failures. The following options were explicitly disabled in the PKGBUILD:

- `opencv` — OpenCV support caused linking errors.
- `va` — Video Acceleration API had missing 32-bit libraries.
- `vulkan` — Vulkan support required 32-bit Vulkan loaders not available in multilib.
- `webrtc` — WebRTC dependencies were incomplete for 32-bit.
- `aja` — AJA video capture library had 32-bit compatibility issues.

These disabled options represent trade-offs: while they reduce functionality, they allow the core library to build successfully.

## 3. Current Status

The build currently fails during the `lib32-gst-plugins-bad-libs` package compilation. The failure is attributed to missing dependencies that were not anticipated in the initial build configuration. Despite disabling the meson options listed above, additional plugins or features in gst-plugins-bad-libs require dependencies that are either not available in 32-bit form or were not included in the build matrix.

The specific error messages would be visible in the GitHub Actions build logs. The next phase of work involves analyzing those logs to identify which additional plugins need to be disabled or which missing dependencies need to be added to the build process.

## Build Progress (Last Updated: Mar 8, 2026)

### Successfully Built Packages (7 total):
1. lib32-gdbm ✅
2. lib32-graphene ✅
3. lib32-libstemmer ✅
4. lib32-avahi ✅
5. lib32-tinysparql ✅
6. lib32-libcloudproviders ✅
7. lib32-gtk4 - Currently building (patch file path just fixed)

### Packages Skipped/Using System Package:
- lib32-gst-plugins-bad-libs - Too problematic, using system package from multilib

### Issues Resolved So Far:
- pacman-key initialization
- multilib repository enabling
- Missing build tools (meson, ninja, etc.)
- Package path resolution in build script
- lib32-icu and lib32-libsoup3 from official repos (not AUR)
- lib32-gdbm checksum fix
- Multiple gst-plugins-bad-libs meson options (opencv, va, vulkan, webrtc, aja, msdk, d3d11)
- Build error detection in scripts
- Workflow exit code handling
- lib32-gtk4 dependency fixes (gst-plugins-bad-libs, vulkan-headers)
- Patch file path issue (just fixed)

### Current Issue:
Just fixed the patch file path - it was in patches/ subdirectory but needed to be next to PKGBUILD. The build is running now.

## 4. How to Work on This Repository

### 4.1 Monitoring Build Status

The primary workflow uses GitHub Actions to execute builds. To work effectively on this repository, follow this iterative process:

First, monitor the workflow runs using the GitHub CLI to see recent build attempts and their status. Identify the most recent run and note its ID for further investigation.

Second, download the build logs from failed runs to diagnose the specific errors. The build logs contain the complete output from makepkg and meson, including compiler errors, missing header files, and configuration failures.

Third, analyze the errors to determine the root cause. Common issues include missing dependencies, incorrect pkgver or sha256sum values, meson configuration problems, and missing 32-bit libraries.

### 4.2 Making Fixes

When fixing issues in this repository, follow these guidelines:

For PKGBUILD modifications, edit the appropriate file in `packages/dependencies/` or `packages/lib32-gtk4/`, ensuring that pkgver, sha256sums, and dependencies are correct. Test changes locally if possible before pushing.

For workflow modifications, edit `.github/workflows/build.yml` to adjust the build matrix, add dependencies, or modify build steps.

For new dependency packages, create a new directory under `packages/dependencies/` with a PKGBUILD and any required patches.

### 4.3 Triggering New Builds

Push changes to the repository to trigger new GitHub Actions workflow runs. Each push will initiate a fresh build attempt. Use the watch command to monitor the build progress in real-time until it completes or fails.

### 4.4 Testing Build Flags Locally

Before pushing to GitHub for CI/CD, you can test build flags locally to avoid many back-and-forth commits:

1. **Clone the repository** to your local Arch Linux machine with multilib enabled

2. **Test meson options** by running the build command with different flags:
   ```bash
   cd packages/dependencies/lib32-gst-plugins-bad-libs
   meson setup build --libdir=/usr/lib32 -D option1=disabled -D option2=enabled
   ```

3. **Check available options**:
   ```bash
   meson configure build  # List all options
   ```

4. **Test if it compiles**:
   ```bash
   meson compile -C build
   ```

5. **If successful**, then update the PKGBUILD with the correct flags and push

This saves time by catching wrong/missing options locally instead of relying on GitHub Actions.

## 5. Key Commands

The following GitHub CLI commands are essential for working with this repository:

### 5.1 Listing Recent Workflow Runs

To see the three most recent workflow runs:

```bash
gh run list --repo os-guy-original/lib32-gtk4-custom-prebuilt --limit 3
```

This command displays the run ID, workflow name, status (success, failure, in_progress), and commit message for each recent attempt. The run ID is required for downloading logs or artifacts.

### 5.2 Downloading Build Logs

To download the build logs from a specific run:

```bash
gh run download <id> --name build-logs --dir /tmp/logs
```

Replace `<id>` with the numeric run ID from the list command. This downloads the build logs to `/tmp/logs`, where they can be examined for error messages. The logs are organized by job and step, making it straightforward to find the specific failure point.

### 5.3 Downloading Built Packages

To download the built packages (if the build succeeds partially):

```bash
gh run download <id> --name lib32-gtk4-packages --dir /tmp/packages
```

This downloads any successfully built packages from the workflow run. Note that failed runs may not have packages available, depending on where the failure occurred.

### 5.4 Monitoring Build Progress

To watch a running build in real-time:

```bash
gh run watch <id> --repo os-guy-original/lib32-gtk4-custom-prebuilt --exit-status
```

This command displays the progress of the specified workflow run and will exit with a non-zero status if the build fails, or zero if it succeeds. This is useful for waiting on a running build without manually checking status repeatedly.

## 6. Common Issues and Solutions

### 6.1 Missing Dependencies

If the build fails with "package not found" errors, identify the missing package and add it to either the main package's dependencies array or create a new dependency package in `packages/dependencies/`.

### 6.2 Checksum Mismatches

If source files have been updated upstream, sha256sums will not match. Run `updpkgsums` in the package directory to update checksums, or manually update them if the sources are trusted.

### 6.3 Meson Configuration Issues

For gst-plugins-bad-libs and similar meson-based packages, if new errors appear, examine the meson_options.txt or run `meson configure` to see available options, then disable problematic features by adding `-Doption=false` to the meson command in the PKGBUILD.

### 6.4 32-bit Library Availability

Some libraries do not have official 32-bit packages in Arch Linux multilib. In these cases, either create a custom lib32 package, disable the feature that requires the library, or find an alternative approach.

## 7. File Structure Reference

The repository is organized as follows:

- `.github/workflows/build.yml` — Main CI/CD workflow definition.
- `packages/lib32-gtk4/` — PKGBUILD and patches for the main lib32-gtk4 package.
- `packages/dependencies/` — PKGBUILDs for custom dependency packages.
- `scripts/` — Helper scripts for building, dependency resolution, and cleanup.
- `aur-reference/` — Original AUR package files for reference.
- `research/` — Experimental or discarded attempts.

Understanding this structure helps locate the appropriate file when making modifications.

## 8. Next Steps for Continuing Work

The immediate priority is to diagnose and fix the lib32-gst-plugins-bad-libs build failure. This involves downloading the most recent build logs, identifying the specific error messages, determining which additional meson options need to be disabled or which dependencies are missing, updating the PKGBUILD accordingly, and pushing the fix to trigger a new build.

After resolving this immediate issue, consider whether additional features can be re-enabled safely, whether there are newer versions of dependencies that might resolve the issues, and whether the build can be optimized or parallelized for faster iteration.
