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
    print('The following commands would be executed to force complete recompilation:');
    for (final pkg in packages) {
      final deactivateArgs = pkg.buildDeactivateArgs();
      final activateArgs = pkg.buildActivateArgs();
      print('  $sdk ${deactivateArgs.join(' ')}');
      print('  $sdk ${activateArgs.join(' ')}');
    }
    print('====================');
    exit(0);
  }

  print('Reinstalling and recompiling packages...');
  for (final pkg in packages) {
    print('--------------------------------------------------');
    print('Processing ${pkg.name} (${pkg.version})...');

    // 1. Deactivate to force recompilation of same-version packages
    final deactivateArgs = pkg.buildDeactivateArgs();
    print('Running: $sdk ${deactivateArgs.join(' ')}');
    final deactRes = Process.runSync(sdk, deactivateArgs);
    if (deactRes.exitCode != 0) {
      print('Warning: Failed to deactivate ${pkg.name}:');
      print(deactRes.stderr);
    }

    // 2. Reactivate with the original source and parameters (including --overwrite)
    final activateArgs = pkg.buildActivateArgs();
    print('Running: $sdk ${activateArgs.join(' ')}');
    final actRes = Process.runSync(sdk, activateArgs);
    if (actRes.exitCode != 0) {
      print('Error: Failed to activate ${pkg.name}!');
      print(actRes.stderr);
      print('');
      print('[ROLLBACK] Attempting to restore ${pkg.name}...');

      // Rollback reactivation attempt
      final rollbackRes = Process.runSync(sdk, activateArgs);
      if (rollbackRes.exitCode != 0) {
        print('[ROLLBACK FAILED] Could not restore ${pkg.name} automatically.');
        print(rollbackRes.stderr);
        print('\nTo manually restore, resolve any network/environment issues and run:');
        print('  $sdk ${activateArgs.join(' ')}\n');
      } else {
        print('[ROLLBACK SUCCESSFUL] Successfully restored ${pkg.name} to its original state.');
      }
    } else {
      final out = actRes.stdout.toString().trim();
      if (out.isNotEmpty) {
        print(out);
      }
      print('Successfully reactivated and recompiled ${pkg.name}!');
    }
  }
  print('--------------------------------------------------');
  print('All done!');
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
