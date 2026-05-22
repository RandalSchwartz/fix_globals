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
    print('The following commands would be executed (atomically overwriting existing activations):');
    for (final pkg in packages) {
      final activateArgs = pkg.buildActivateArgs();
      print('  $sdk ${activateArgs.join(' ')}');
    }
    print('====================');
    exit(0);
  }

  print('Reinstalling packages atomically...');
  for (final pkg in packages) {
    print('--------------------------------------------------');
    print('Reinstalling ${pkg.name} (${pkg.version})...');

    final activateArgs = pkg.buildActivateArgs();
    print('Running: $sdk ${activateArgs.join(' ')}');
    final actRes = Process.runSync(sdk, activateArgs);
    if (actRes.exitCode != 0) {
      print('Error: Failed to reinstall ${pkg.name}:');
      print(actRes.stderr);
      print('Safe Overwrite Protection: The previous installation of ${pkg.name} remains active and untouched.');
    } else {
      final out = actRes.stdout.toString().trim();
      if (out.isNotEmpty) {
        print(out);
      }
      print('Successfully reactivated ${pkg.name}!');
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
