import 'dart:async';
import 'dart:io';
import 'package:fix_globals/fix_globals.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../bin/fix_globals.dart';

void main() {
  group('printUsage tests', () {
    test('prints expected usage options', () {
      final log = <String>[];
      final parser = buildArgParser();
      runZoned(
        () => printUsage(parser),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => log.add(line),
        ),
      );

      final output = log.join('\n');
      expect(output, contains('Usage: fix-globals [options]'));
      expect(output, contains('--dry-run'));
      expect(output, contains('--update'));
      expect(output, contains('--help'));
    });
  });

  group('printDryRun tests', () {
    final samplePackages = [
      GlobalPackage(
        name: 'dhttpd',
        version: '4.0.0',
        source: PackageSource.hosted,
      ),
      GlobalPackage(
        name: 'local_tool',
        version: '1.0.0',
        source: PackageSource.path,
        origin: '/Users/test/local_tool',
      ),
      GlobalPackage(
        name: 'git_tool',
        version: '2.0.0',
        source: PackageSource.git,
        origin: 'https://github.com/test/repo',
        gitRef: 'main',
        gitPath: 'packages/git_tool',
      ),
      GlobalPackage(
        name: 'custom_tool',
        version: '3.0.0',
        source: PackageSource.customHosted,
        origin: 'https://my-pub.org',
      ),
    ];

    test('prints commands for recompile mode (update: false)', () {
      final log = <String>[];
      runZoned(
        () => printDryRun(samplePackages, update: false),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => log.add(line),
        ),
      );

      final output = log.join('\n');
      expect(output, contains('=== DRY RUN MODE ==='));
      expect(
        output,
        contains(
          'The following commands would be executed to force complete recompilation:',
        ),
      );
      expect(output, contains('dart uninstall dhttpd'));
      expect(output, contains('dart install dhttpd --overwrite'));
      expect(output, contains('dart uninstall local_tool'));
      expect(
        output,
        contains(
          'dart install local_tool@{path: /Users/test/local_tool} --overwrite',
        ),
      );
      expect(output, contains('dart uninstall git_tool'));
      expect(
        output,
        contains(
          'dart install git_tool@{git: {url: https://github.com/test/repo, ref: main, path: packages/git_tool}} --overwrite',
        ),
      );
      expect(output, contains('dart uninstall custom_tool'));
      expect(
        output,
        contains(
          'dart install custom_tool@{hosted: https://my-pub.org} --overwrite',
        ),
      );
      expect(output, contains('===================='));
    });

    test('prints commands for update mode (update: true)', () {
      final log = <String>[];
      runZoned(
        () => printDryRun(samplePackages, update: true),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => log.add(line),
        ),
      );

      final output = log.join('\n');
      expect(output, contains('=== DRY RUN MODE ==='));
      expect(
        output,
        contains(
          'The following commands would be executed to pull package updates:',
        ),
      );
      expect(output, isNot(contains('uninstall')));
      expect(output, contains('dart install dhttpd --overwrite'));
      expect(
        output,
        contains(
          'dart install local_tool@{path: /Users/test/local_tool} --overwrite',
        ),
      );
      expect(output, contains('===================='));
    });
  });

  group('executePackageReinstalls tests', () {
    final pkgHosted = GlobalPackage(
      name: 'pkg_a',
      version: '1.0.0',
      source: PackageSource.hosted,
    );

    test('reinstallation flow (update: false) succeeds', () async {
      final executedCommands = <List<String>>[];
      final results = await executePackageReinstalls(
        [pkgHosted],
        update: false,
        processRunner: (exec, args) async {
          executedCommands.add([exec, ...args]);
          return ProcessResult(1234, 0, 'Installed successfully\n', '');
        },
      );

      expect(executedCommands, hasLength(2));
      expect(executedCommands[0], equals(['dart', 'uninstall', 'pkg_a']));
      expect(
        executedCommands[1],
        equals(['dart', 'install', 'pkg_a', '--overwrite']),
      );

      expect(results, hasLength(1));
      expect(results[0].name, equals('pkg_a'));
      expect(results[0].initialVersion, equals('1.0.0'));
      expect(results[0].status, equals(ReinstallStatus.success));
      expect(results[0].error, isNull);
    });

    test('update flow skips package when already up to date', () async {
      final executedCommands = <List<String>>[];
      final results = await executePackageReinstalls(
        [pkgHosted],
        update: true,
        latestVersionFetcher: (pkg, registry) async => '1.0.0',
        processRunner: (exec, args) async {
          executedCommands.add([exec, ...args]);
          return ProcessResult(1234, 0, '', '');
        },
      );

      expect(executedCommands, isEmpty);
      expect(results, hasLength(1));
      expect(results[0].name, equals('pkg_a'));
      expect(results[0].initialVersion, equals('1.0.0'));
      expect(results[0].status, equals(ReinstallStatus.success));
    });

    test(
      'update flow installs package when new version is available',
      () async {
        final executedCommands = <List<String>>[];
        final results = await executePackageReinstalls(
          [pkgHosted],
          update: true,
          latestVersionFetcher: (pkg, registry) async => '1.1.0',
          processRunner: (exec, args) async {
            executedCommands.add([exec, ...args]);
            return ProcessResult(1234, 0, 'Updated to 1.1.0\n', '');
          },
        );

        expect(executedCommands, hasLength(1));
        expect(
          executedCommands[0],
          equals(['dart', 'install', 'pkg_a', '--overwrite']),
        );
        expect(results, hasLength(1));
        expect(results[0].status, equals(ReinstallStatus.success));
      },
    );

    test('failure with successful rollback (update: false)', () async {
      final executedCommands = <List<String>>[];
      final results = await executePackageReinstalls(
        [pkgHosted],
        update: false,
        processRunner: (exec, args) async {
          executedCommands.add([exec, ...args]);
          if (args.contains('uninstall')) {
            return ProcessResult(1234, 0, '', '');
          }
          if (executedCommands.length == 2) {
            // First install attempt fails
            return ProcessResult(1234, 1, '', 'Compilation error');
          }
          // Rollback install attempt succeeds
          return ProcessResult(1234, 0, 'Restored original\n', '');
        },
      );

      expect(executedCommands, hasLength(3));
      expect(executedCommands[0], equals(['dart', 'uninstall', 'pkg_a']));
      expect(
        executedCommands[1],
        equals(['dart', 'install', 'pkg_a', '--overwrite']),
      );
      expect(
        executedCommands[2],
        equals(['dart', 'install', 'pkg_a', '--overwrite']),
      );

      expect(results, hasLength(1));
      expect(results[0].status, equals(ReinstallStatus.rolledBack));
      expect(results[0].error, isNull);
    });

    test(
      'failure with double-fault rollback failure (update: false)',
      () async {
        final executedCommands = <List<String>>[];
        final results = await executePackageReinstalls(
          [pkgHosted],
          update: false,
          processRunner: (exec, args) async {
            executedCommands.add([exec, ...args]);
            if (args.contains('uninstall')) {
              return ProcessResult(1234, 0, '', '');
            }
            // Both install and rollback fail
            return ProcessResult(1234, 1, '', 'Persistent network failure');
          },
        );

        expect(executedCommands, hasLength(3));
        expect(results, hasLength(1));
        expect(results[0].status, equals(ReinstallStatus.failed));
        expect(results[0].error, contains('Persistent network failure'));
      },
    );

    test('reinstallation continues and warns when uninstall fails', () async {
      final log = <String>[];
      final executedCommands = <List<String>>[];
      final results = await runZoned(
        () => executePackageReinstalls(
          [pkgHosted],
          update: false,
          processRunner: (exec, args) async {
            executedCommands.add([exec, ...args]);
            if (args.contains('uninstall')) {
              return ProcessResult(1234, 1, '', 'Uninstall warning details');
            }
            return ProcessResult(1234, 0, 'Installed', '');
          },
        ),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => log.add(line),
        ),
      );

      expect(executedCommands, hasLength(2));
      expect(log.join('\n'), contains('Warning: Failed to uninstall pkg_a:'));
      expect(log.join('\n'), contains('Uninstall warning details'));
      expect(results, hasLength(1));
      expect(results[0].status, equals(ReinstallStatus.success));
    });

    test(
      'update flow on git and path packages proceeds without registry version check',
      () async {
        final gitPkg = GlobalPackage(
          name: 'pkg_git',
          version: '1.0.0',
          source: PackageSource.git,
          origin: 'https://github.com/test/repo',
        );
        final executedCommands = <List<String>>[];
        bool fetcherCalled = false;
        final results = await executePackageReinstalls(
          [gitPkg],
          update: true,
          latestVersionFetcher: (pkg, registry) async {
            fetcherCalled = true;
            return null;
          },
          processRunner: (exec, args) async {
            executedCommands.add([exec, ...args]);
            return ProcessResult(1234, 0, 'Updated git', '');
          },
        );

        expect(fetcherCalled, isFalse);
        expect(executedCommands, hasLength(1));
        expect(
          executedCommands[0],
          equals([
            'dart',
            'install',
            'pkg_git@{git: {url: https://github.com/test/repo}}',
            '--overwrite',
          ]),
        );
        expect(results, hasLength(1));
        expect(results[0].status, equals(ReinstallStatus.success));
      },
    );

    test(
      'update failure reports failed without rollback (update: true)',
      () async {
        final executedCommands = <List<String>>[];
        final results = await executePackageReinstalls(
          [pkgHosted],
          update: true,
          latestVersionFetcher: (pkg, registry) async => '2.0.0',
          processRunner: (exec, args) async {
            executedCommands.add([exec, ...args]);
            return ProcessResult(1234, 1, '', 'Update failed');
          },
        );

        expect(executedCommands, hasLength(1));
        expect(results, hasLength(1));
        expect(results[0].status, equals(ReinstallStatus.failed));
        expect(results[0].error, contains('Update failed'));
      },
    );

    test(
      'update flow executes version checks concurrently across packages',
      () async {
        final pkg1 = GlobalPackage(
          name: 'pkg_one',
          version: '1.0.0',
          source: PackageSource.hosted,
        );
        final pkg2 = GlobalPackage(
          name: 'pkg_two',
          version: '1.0.0',
          source: PackageSource.hosted,
        );

        final checkOrder = <String>[];
        int activeChecks = 0;
        int maxConcurrentChecks = 0;

        final results = await executePackageReinstalls(
          [pkg1, pkg2],
          update: true,
          latestVersionFetcher: (pkg, registry) async {
            activeChecks++;
            if (activeChecks > maxConcurrentChecks) {
              maxConcurrentChecks = activeChecks;
            }
            checkOrder.add('start_$pkg');
            await Future.delayed(const Duration(milliseconds: 50));
            checkOrder.add('end_$pkg');
            activeChecks--;
            return '1.0.0'; // up to date
          },
          processRunner: (exec, args) async => ProcessResult(1, 0, '', ''),
        );

        expect(maxConcurrentChecks, equals(2));
        expect(results, hasLength(2));
        expect(results[0].status, equals(ReinstallStatus.success));
        expect(results[1].status, equals(ReinstallStatus.success));
      },
    );
  });

  group('printSummaryTable tests', () {
    late Directory tempInstallDir;

    setUp(() async {
      tempInstallDir = await Directory.systemTemp.createTemp(
        'fix_globals_summary_test_',
      );
      final appBundles = Directory(p.join(tempInstallDir.path, 'app-bundles'));
      await appBundles.create(recursive: true);

      // Create dummy lock files for scanned packages:
      // pkg_success: version 1.0.0 (recompiled / up to date)
      // pkg_updated: version 2.0.0 (updated from 1.0.0)
      final pkgSuccessDir = Directory(p.join(appBundles.path, 'pkg_success'));
      await pkgSuccessDir.create();
      await File(p.join(pkgSuccessDir.path, 'pubspec.lock')).writeAsString('''
packages:
  pkg_success:
    description:
      name: pkg_success
      url: "https://pub.dev"
    source: hosted
    version: "1.0.0"
''');

      final pkgUpdatedDir = Directory(p.join(appBundles.path, 'pkg_updated'));
      await pkgUpdatedDir.create();
      await File(p.join(pkgUpdatedDir.path, 'pubspec.lock')).writeAsString('''
packages:
  pkg_updated:
    description:
      name: pkg_updated
      url: "https://pub.dev"
    source: hosted
    version: "2.0.0"
''');
    });

    tearDown(() async {
      await tempInstallDir.delete(recursive: true);
    });

    test(
      'prints summary table accurately for recompile mode (update: false)',
      () {
        final results = [
          PackageReinstallResult(
            name: 'pkg_success',
            initialVersion: '1.0.0',
            status: ReinstallStatus.success,
          ),
          PackageReinstallResult(
            name: 'pkg_rolled_back',
            initialVersion: '1.5.0',
            status: ReinstallStatus.rolledBack,
          ),
          PackageReinstallResult(
            name: 'pkg_failed',
            initialVersion: '0.8.0',
            status: ReinstallStatus.failed,
            error: 'Reinstall failed',
          ),
        ];

        final log = <String>[];
        runZoned(
          () => printSummaryTable(results, tempInstallDir, update: false),
          zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, line) => log.add(line),
          ),
        );

        final output = log.join('\n');
        expect(output, contains('REINSTALLATION SUMMARY'));
        expect(
          output,
          contains('Package                   Status        Version Change'),
        );
        expect(
          output,
          contains(
            'pkg_success               Success       1.0.0 (recompiled)',
          ),
        );
        expect(
          output,
          contains(
            'pkg_rolled_back           Rolled Back   1.5.0 -> [Uninstalled]',
          ),
        );
        expect(
          output,
          contains(
            'pkg_failed                Failed        0.8.0 -> [Uninstalled]',
          ),
        );
        expect(output, contains('All done!'));
      },
    );

    test('prints summary table accurately for update mode (update: true)', () {
      final results = [
        PackageReinstallResult(
          name: 'pkg_success',
          initialVersion: '1.0.0',
          status: ReinstallStatus.success,
        ),
        PackageReinstallResult(
          name: 'pkg_updated',
          initialVersion: '1.0.0',
          status: ReinstallStatus.success,
        ),
        PackageReinstallResult(
          name: 'pkg_failed',
          initialVersion: '0.5.0',
          status: ReinstallStatus.failed,
          error: 'Update failed',
        ),
      ];

      final log = <String>[];
      runZoned(
        () => printSummaryTable(results, tempInstallDir, update: true),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => log.add(line),
        ),
      );

      final output = log.join('\n');
      expect(output, contains('REINSTALLATION SUMMARY'));
      expect(
        output,
        contains('pkg_success               Success       1.0.0 (up to date)'),
      );
      expect(
        output,
        contains('pkg_updated               Success       1.0.0 -> 2.0.0'),
      );
      expect(
        output,
        contains(
          'pkg_failed                Failed        0.5.0 -> [Failed to Update]',
        ),
      );
    });
  });
}
