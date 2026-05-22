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
