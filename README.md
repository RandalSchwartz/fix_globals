# fix_globals

[![Pub Version](https://img.shields.io/pub/v/fix_globals.svg)](https://pub.dev/packages/fix_globals)
[![License](https://img.shields.io/badge/license-BSD_3--Clause-blue.svg)](LICENSE)

A robust, lightweight command-line utility to cleanly reinstall and refresh all globally activated Dart and Flutter packages from their original sources (pub.dev, local paths, git repositories, and custom hosted registries).

This utility parses your current globally activated packages, deactivates them, and reactivates them using their original settings—perfect for when a Dart SDK upgrade breaks global links, when switching Dart tool managers (such as Puro), or when you just want to refresh all your active global tools.

---

## Features

- **Multi-Source Support**: Seamlessly detects and re-installs packages from:
  - 🌐 **pub.dev** (standard hosted packages)
  - 📂 **Local path** (`at path`)
  - 🐙 **Git repositories** (including custom references/branches and sub-paths)
  - 🏠 **Custom registries** (`at hosted` custom servers)
- **Safe Dry-Run Mode**: See exactly what actions will be taken without modifying any packages on disk using `--dry-run` (`-n`).
- **Flexible SDK Targets**: Choose whether to run the reactivation processes using `dart` or `flutter` globally with `--sdk` (`-s`).
- **Robust Execution**: Runs sequentially and logs all success/failure status clearly.

---

## Installation

Activate `fix_globals` globally via the Dart SDK:

```bash
dart pub global activate fix_globals
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
| `--dry-run` | `-n` | Show the activation commands that would be executed without running them. |
| `--sdk` | `-s` | The SDK executable to use for activation (`dart` or `flutter`). [default: `dart`] |
| `--help` | `-h` | Print this usage help menu. |

---

## Example

```bash
$ fix-globals --dry-run
[info] Parsing globally activated packages...
[info] Found 3 activated packages.
[info] [Dry-Run] Would deactivate dcm
[info] [Dry-Run] Would activate dcm at path "/Users/username/Projects/dcm"
[info] [Dry-Run] Would deactivate melos
[info] [Dry-Run] Would activate melos from git "https://github.com/invertase/melos.git"
[info] [Dry-Run] Would deactivate sass
[info] [Dry-Run] Would activate sass from pub.dev
[info] Dry-run complete. No changes were made.
```

## License

This project is licensed under the BSD 3-Clause License - see the [LICENSE](LICENSE) file for details.
