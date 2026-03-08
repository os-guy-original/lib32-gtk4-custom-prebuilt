# lib32-gtk4-custom Prebuilt Repository

## Installation

1. Add the repository to `/etc/pacman.conf`:

```bash
# Add this to the end of /etc/pacman.conf:
[lib32-gtk4-custom]
Server = https://github.com/os-guy-original/lib32-gtk4-custom-prebuilt/raw/main/repo
```

2. Refresh the package database:

```bash
sudo pacman -Sy
```

3. Install the package:

```bash
sudo pacman -S lib32-gtk4
```

## Updating the Repository

Run the update script:

```bash
./update-repo.sh
```

This will rebuild the database from packages in the `../releases/` directory.

## Manual Installation

You can also download packages directly from the releases directory and install with:

```bash
sudo pacman -U <package-file>
```
