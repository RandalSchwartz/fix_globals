import 'dart:io';
import 'package:args/args.dart';
import 'package:fix_globals/fix_globals.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag(
      'dry-run',
      abbr: 'n',
      negatable: false,
      help: 'Show what would be done without making changes.',
    )
    ..addFlag(
      'update',
      abbr: 'u',
      negatable: false,
      help: 'Only pull package updates and skip uninstallation.',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show this help message.',
    );

  ArgResults argResults;
  try {
    argResults = parser.parse(arguments);
  } on FormatException catch (e) {
    print('Error: ${e.message}');
    print('');
    printUsage(parser);
    exit(1);
  }

  if (argResults['help'] as bool) {
    printUsage(parser);
    exit(0);
  }

  final dryRun = argResults['dry-run'] as bool;
  final update = argResults['update'] as bool;

  final installDir = getDartInstallDir();
  print('Scanning globally installed packages in:');
  print('  ${installDir.path}');
  print('');

  final packages = scanInstalledPackages(installDir);

  if (packages.isEmpty) {
    print('No globally installed Dart CLI packages found.');
    exit(0);
  }

  print('Found ${packages.length} globally installed package(s):');
  for (final pkg in packages) {
    print('  - $pkg');
  }
  print('');

  if (dryRun) {
    print('=== DRY RUN MODE ===');
    if (update) {
      print('The following commands would be executed to pull package updates:');
      for (final pkg in packages) {
        final activateArgs = pkg.buildActivateArgs(update: true);
        print('  dart ${activateArgs.join(' ')}');
      }
    } else {
      print(
        'The following commands would be executed to force complete recompilation:',
      );
      for (final pkg in packages) {
        final deactivateArgs = pkg.buildDeactivateArgs();
        final activateArgs = pkg.buildActivateArgs(update: false);
        print('  dart ${deactivateArgs.join(' ')}');
        print('  dart ${activateArgs.join(' ')}');
      }
    }
    print('====================');
    exit(0);
  }

  if (update) {
    print('Updating packages...');
  } else {
    print('Reinstalling and recompiling packages...');
  }
  final results = <PackageReinstallResult>[];
  for (final pkg in packages) {
    print('--------------------------------------------------');
    print('Processing ${pkg.name} (${pkg.version})...');

    bool shouldInstall = true;
    if (update && (pkg.source == PackageSource.hosted || pkg.source == PackageSource.customHosted)) {
      final registryUrl = pkg.source == PackageSource.hosted ? 'https://pub.dev' : pkg.origin!;
      print('Checking for updates from $registryUrl...');
      final latest = await fetchLatestVersion(pkg.name, registryUrl);
      if (latest != null) {
        if (latest == pkg.version) {
          print('  ${pkg.name} is already up to date (${pkg.version}). Skipping.');
          shouldInstall = false;
          results.add(
            PackageReinstallResult(
              name: pkg.name,
              initialVersion: pkg.version,
              status: ReinstallStatus.success,
            ),
          );
        } else {
          print('  New version available: ${pkg.version} -> $latest');
        }
      }
    }

    if (shouldInstall) {
      if (!update) {
        // 1. Uninstall to force recompilation of same-version packages
        final deactivateArgs = pkg.buildDeactivateArgs();
        print('Running: dart ${deactivateArgs.join(' ')}');
        final deactRes = Process.runSync('dart', deactivateArgs);
        if (deactRes.exitCode != 0) {
          print('Warning: Failed to uninstall ${pkg.name}:');
          print(deactRes.stderr);
        }
      }

      // 2. Install with the original source and parameters (including --overwrite)
      final activateArgs = pkg.buildActivateArgs(update: update);
      print('Running: dart ${activateArgs.join(' ')}');
      final actRes = Process.runSync('dart', activateArgs);
      if (actRes.exitCode != 0) {
        print('Error: Failed to install ${pkg.name}!');
        print(actRes.stderr);
        print('');

        if (!update) {
          print('[ROLLBACK] Attempting to restore original version ${pkg.name} (${pkg.version})...');

          // Rollback reactivation attempt using the original descriptor
          final rollbackArgs = pkg.buildActivateArgs(update: false);
          final rollbackRes = Process.runSync('dart', rollbackArgs);
          if (rollbackRes.exitCode != 0) {
            print('[ROLLBACK FAILED] Could not restore ${pkg.name} automatically.');
            print(rollbackRes.stderr);
            print(
              '\nTo manually restore, resolve any network/environment issues and run:',
            );
            print('  dart ${rollbackArgs.join(' ')}\n');
            results.add(
              PackageReinstallResult(
                name: pkg.name,
                initialVersion: pkg.version,
                status: ReinstallStatus.failed,
                error: actRes.stderr.toString(),
              ),
            );
          } else {
            print(
              '[ROLLBACK SUCCESSFUL] Successfully restored ${pkg.name} to its original state.',
            );
            results.add(
              PackageReinstallResult(
                name: pkg.name,
                initialVersion: pkg.version,
                status: ReinstallStatus.rolledBack,
              ),
            );
          }
        } else {
          // For updates, the old version is still safely active on error
          results.add(
            PackageReinstallResult(
              name: pkg.name,
              initialVersion: pkg.version,
              status: ReinstallStatus.failed,
              error: actRes.stderr.toString(),
            ),
          );
        }
      } else {
        final out = actRes.stdout.toString().trim();
        if (out.isNotEmpty) {
          print(out);
        }
        if (update) {
          print('Successfully updated/checked ${pkg.name}!');
        } else {
          print('Successfully reinstalled and recompiled ${pkg.name}!');
        }
        results.add(
          PackageReinstallResult(
            name: pkg.name,
            initialVersion: pkg.version,
            status: ReinstallStatus.success,
          ),
        );
      }
    }
  }

  print('--------------------------------------------------');
  print('Fetching final package versions...');
  final finalPackages = scanInstalledPackages(installDir);
  final Map<String, String> finalVersions = {
    for (final pkg in finalPackages) pkg.name: pkg.version
  };

  print('\n==================================================');
  print('            REINSTALLATION SUMMARY');
  print('==================================================');
  print('${'Package'.padRight(25)} ${'Status'.padRight(13)} Version Change');
  print('--------------------------------------------------');
  for (final res in results) {
    final name = res.name;
    final statusStr = res.status == ReinstallStatus.success
        ? 'Success'
        : res.status == ReinstallStatus.rolledBack
        ? 'Rolled Back'
        : 'Failed';

    final finalVer = finalVersions[name];
    String versionChange;
    if (res.status == ReinstallStatus.failed || finalVer == null) {
      if (update) {
        versionChange = '${res.initialVersion} -> [Failed to Update]';
      } else {
        versionChange = '${res.initialVersion} -> [Uninstalled]';
      }
    } else if (res.initialVersion == finalVer) {
      versionChange = update
          ? '${res.initialVersion} (up to date)'
          : '${res.initialVersion} (recompiled)';
    } else {
      versionChange = '${res.initialVersion} -> $finalVer';
    }

    print('${name.padRight(25)} ${statusStr.padRight(13)} $versionChange');
  }
  print('==================================================');
  print('All done!');
}

enum ReinstallStatus { success, rolledBack, failed }

class PackageReinstallResult {
  final String name;
  final String initialVersion;
  final ReinstallStatus status;
  final String? error;

  PackageReinstallResult({
    required this.name,
    required this.initialVersion,
    required this.status,
    this.error,
  });
}

void printUsage(ArgParser parser) {
  print('Usage: fix-globals [options]');
  print(
    'Reinstalls (uninstalls and reinstalls) all globally installed Dart CLI packages.',
  );
  print('');
  print('Options:');
  print(parser.usage);
}
