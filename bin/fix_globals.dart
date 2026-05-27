import 'dart:io';
import 'package:args/args.dart';
import 'package:fix_globals/fix_globals.dart';

void main(List<String> arguments) {
  final parser = ArgParser()
    ..addFlag(
      'dry-run',
      abbr: 'n',
      negatable: false,
      help: 'Show what would be done without making changes.',
    )
    ..addOption(
      'sdk',
      abbr: 's',
      allowed: ['dart', 'flutter'],
      defaultsTo: 'flutter',
      help: 'SDK to use: "flutter" or "dart".',
    )
    ..addFlag(
      'update',
      abbr: 'u',
      negatable: false,
      help: 'Only pull package updates and skip deactivation.',
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
  final sdk = argResults['sdk'] as String;
  final update = argResults['update'] as bool;

  print('Fetching globally activated packages using "$sdk pub global list"...');
  final listResult = Process.runSync(sdk, ['pub', 'global', 'list']);
  if (listResult.exitCode != 0) {
    print('Error running "$sdk pub global list":');
    print(listResult.stderr);
    exit(listResult.exitCode);
  }

  final lines = listResult.stdout.toString().split('\n');
  final packages = <GlobalPackage>[];
  for (final line in lines) {
    final pkg = parsePubGlobalLine(line);
    if (pkg != null) {
      packages.add(pkg);
    }
  }

  if (packages.isEmpty) {
    print('No globally activated packages found for SDK "$sdk".');
    exit(0);
  }

  print('Found ${packages.length} globally activated package(s):');
  for (final pkg in packages) {
    print('  - $pkg');
  }
  print('');

  if (dryRun) {
    print('=== DRY RUN MODE ===');
    if (update) {
      print('The following commands would be executed to pull package updates:');
      for (final pkg in packages) {
        final activateArgs = pkg.buildActivateArgs();
        print('  $sdk ${activateArgs.join(' ')}');
      }
    } else {
      print(
        'The following commands would be executed to force complete recompilation:',
      );
      for (final pkg in packages) {
        final deactivateArgs = pkg.buildDeactivateArgs();
        final activateArgs = pkg.buildActivateArgs();
        print('  $sdk ${deactivateArgs.join(' ')}');
        print('  $sdk ${activateArgs.join(' ')}');
      }
    }
    print('====================');
    exit(0);
  }

  if (update) {
    print('Updating and reactivating packages...');
  } else {
    print('Reinstalling and recompiling packages...');
  }
  final results = <PackageReinstallResult>[];
  for (final pkg in packages) {
    print('--------------------------------------------------');
    print('Processing ${pkg.name} (${pkg.version})...');

    if (!update) {
      // 1. Deactivate to force recompilation of same-version packages
      final deactivateArgs = pkg.buildDeactivateArgs();
      print('Running: $sdk ${deactivateArgs.join(' ')}');
      final deactRes = Process.runSync(sdk, deactivateArgs);
      if (deactRes.exitCode != 0) {
        print('Warning: Failed to deactivate ${pkg.name}:');
        print(deactRes.stderr);
      }
    }

    // 2. Reactivate with the original source and parameters (including --overwrite)
    final activateArgs = pkg.buildActivateArgs();
    print('Running: $sdk ${activateArgs.join(' ')}');
    final actRes = Process.runSync(sdk, activateArgs);
    if (actRes.exitCode != 0) {
      print('Error: Failed to activate ${pkg.name}!');
      print(actRes.stderr);
      print('');

      if (!update) {
        print('[ROLLBACK] Attempting to restore ${pkg.name}...');

        // Rollback reactivation attempt
        final rollbackRes = Process.runSync(sdk, activateArgs);
        if (rollbackRes.exitCode != 0) {
          print('[ROLLBACK FAILED] Could not restore ${pkg.name} automatically.');
          print(rollbackRes.stderr);
          print(
            '\nTo manually restore, resolve any network/environment issues and run:',
          );
          print('  $sdk ${activateArgs.join(' ')}\n');
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
        print('Successfully reactivated and recompiled ${pkg.name}!');
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

  print('--------------------------------------------------');
  print('Fetching final package versions...');
  final finalResult = Process.runSync(sdk, ['pub', 'global', 'list']);
  final Map<String, String> finalVersions = {};
  if (finalResult.exitCode == 0) {
    final finalLines = finalResult.stdout.toString().split('\n');
    for (final line in finalLines) {
      final pkg = parsePubGlobalLine(line);
      if (pkg != null) {
        finalVersions[pkg.name] = pkg.version;
      }
    }
  }

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
        versionChange = '${res.initialVersion} -> [Deactivated]';
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
    'Reinstalls (deactivates and reactivates) all globally activated pub packages.',
  );
  print('');
  print('Options:');
  print(parser.usage);
}
