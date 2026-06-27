# fix_globals

[![Pub Version](https://img.shields.io/pub/v/fix_globals.svg)](https://pub.dev/packages/fix_globals)
[![License](https://img.shields.io/badge/license-BSD_3--Clause-blue.svg)](LICENSE)

A robust, lightweight command-line utility to cleanly reinstall and refresh all globally installed Dart CLI packages from their original sources (pub.dev, local paths, git repositories, and custom hosted registries).

This utility scans your current globally installed package bundles, uninstalls them, and reinstalls them using their original descriptors—perfect for when a Dart SDK upgrade breaks global links, when switching Dart tool managers, or when you just want to refresh all your active global tools.

It has been completely rewritten to support the new `dart install`, `dart installed`, and `dart uninstall` package management commands, replacing the legacy `pub global` commands.

---

## Features

- **Multi-Source Support**: Seamlessly detects and re-installs packages from:
  - 🌐 **pub.dev** (standard hosted packages)
  - 📂 **Local path** (`path` packages)
  - 🐙 **Git repositories** (including custom references/branches and sub-paths)
  - 🏠 **Custom registries** (`hosted` custom servers)
- **Safe Dry-Run Mode**: See exactly what actions will be taken without modifying any packages on disk using `--dry-run` (`-n`).
- **Update Mode (Cron Friendly)**: Pull new package versions without clean-slating or uninstalling them first using `--update` (`-u`).
- **Robust Execution**: Runs sequentially and logs all success/failure status clearly.

---

## Installation

Install `fix_globals` globally via the Dart SDK:

```bash
dart install fix_globals
```

---

## Usage

Run the utility:

```bash
fix-globals [options]
```

### Options

| Option | Alias | Description |
|---|---|---|
| `--dry-run` | `-n` | Show the installation commands that would be executed without running them. |
| `--update` | `-u` | Skip uninstalling packages. Useful in a daily cron job to quickly pull and bind the latest versions of your packages without the expense of a full reinstall/recompile of same-version packages. |
| `--help` | `-h` | Print this usage help menu. |

---

### Default Mode vs. Update Mode

- **Default Mode** (no extra flags): Clears out the existing installation state using `dart uninstall` first, then completely downloads/re-clones and recompiles each package using `dart install`. This is useful when upgrading your Dart SDK to guarantee that every package's precompiled binaries are rebuilt for compatibility with the new SDK.
- **Update Mode (`--update` / `-u`)**: Bypasses the `dart uninstall` step. It behaves like a standard `dart install --overwrite` command. It runs extremely fast for packages already at the latest version, while still fetching and compiling any newly released versions or local path/git packages that have new changes. Perfect for a regular scheduler or daily cron job.

---

## Example

```bash
$ fix-globals --dry-run
Scanning globally installed packages in:
  /Users/username/Library/Application Support/Dart/install

Found 3 globally installed package(s):
  - jaspr_cli 0.23.1
  - melos 7.4.0
  - coverage 1.15.0

=== DRY RUN MODE ===
The following commands would be executed to force complete recompilation:
  dart uninstall jaspr_cli
  dart install jaspr_cli@0.23.1 --overwrite
  dart uninstall melos
  dart install melos@7.4.0 --overwrite
  dart uninstall coverage
  dart install coverage@1.15.0 --overwrite
====================
```

## License

This project is licensed under the BSD 3-Clause License - see the [LICENSE](LICENSE) file for details.
