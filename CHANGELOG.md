## 1.1.0

- Added the `--update` / `-u` CLI flag. When active, it bypasses the package deactivation step to quickly pull updates for active packages and repair bound shims.
- Updated the dry-run output to only display activation commands when in update mode.
- Enhanced the end-of-execution summary table to show `(up to date)` or `[Failed to Update]` statuses.
- Added comprehensive documentation comparing Default Mode vs. Update Mode in the README.

## 1.0.1

- Explicitly declared supported desktop platforms (Linux, macOS, Windows) in `pubspec.yaml` to exclude non-applicable mobile/web platform tags on pub.dev.

## 1.0.0

- Initial release of `fix_globals`!
- Parses currently activated global packages from `pub.dev`, local path, git repositories, and custom hosted registries.
- Deactivates and cleanly reactivates packages to force re-compilation of same-version packages (essential for fixing stale/broken global binaries after Dart SDK upgrades).
- Standard CLI argument parser with support for:
  - `--dry-run` / `-n` to preview reinstallation commands.
  - `--sdk` / `-s` to choose between running processes via `dart` or `flutter`.
  - `--help` / `-h` for usage help.
- Implements automated rollback safety on reactivation failure to prevent package loss.
- Displays a clean, readable Reinstallation Summary table at the end of execution.
