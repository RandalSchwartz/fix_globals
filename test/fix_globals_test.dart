import 'dart:convert';
import 'dart:io';
import 'package:fix_globals/fix_globals.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('GlobalPackage Model tests', () {
    test('buildDeactivateArgs returns correct uninstall command', () {
      final pkg = GlobalPackage(
        name: 'my_cli',
        version: '1.0.0',
        source: PackageSource.hosted,
      );
      expect(pkg.buildDeactivateArgs(), equals(['uninstall', 'my_cli']));
    });

    test('toString formats all PackageSource types correctly', () {
      final hosted = GlobalPackage(
        name: 'pkg_a',
        version: '1.0.0',
        source: PackageSource.hosted,
      );
      expect(hosted.toString(), equals('pkg_a 1.0.0'));

      final pathPkg = GlobalPackage(
        name: 'pkg_b',
        version: '2.0.0',
        source: PackageSource.path,
        origin: '/path/to/pkg',
      );
      expect(pathPkg.toString(), equals('pkg_b 2.0.0 at path "/path/to/pkg"'));

      final gitPkg = GlobalPackage(
        name: 'pkg_c',
        version: '3.0.0',
        source: PackageSource.git,
        origin: 'https://github.com/org/repo',
        gitRef: 'v3.0.0',
        gitPath: 'packages/pkg_c',
      );
      expect(
        gitPkg.toString(),
        equals(
          'pkg_c 3.0.0 from git "https://github.com/org/repo" ref "v3.0.0" path "packages/pkg_c"',
        ),
      );

      final customHosted = GlobalPackage(
        name: 'pkg_d',
        version: '4.0.0',
        source: PackageSource.customHosted,
        origin: 'https://onepub.dev',
      );
      expect(
        customHosted.toString(),
        equals('pkg_d 4.0.0 at hosted "https://onepub.dev"'),
      );
    });
  });

  group('getDartInstallDir tests', () {
    test('resolves directory path given explicit environment', () {
      final env = {'HOME': '/mock/home'};
      final dir = getDartInstallDir(environment: env);
      expect(dir.path, contains('/mock/home'));
    });

    test('throws StateError when HOME and USERPROFILE are missing', () {
      expect(() => getDartInstallDir(environment: {}), throwsStateError);
    });
  });

  group('Lockfile & Directory Scanning tests', () {
    test(
      'parsePackageFromYaml parses hosted, path, git, and customHosted packages',
      () {
        const hostedYaml = '''
packages:
  foo:
    dependency: "direct main"
    description:
      name: foo
      url: "https://pub.dev"
    source: hosted
    version: "1.2.3"
''';
        final pkg1 = parsePackageFromYaml(hostedYaml, 'foo');
        expect(pkg1, isNotNull);
        expect(pkg1!.name, equals('foo'));
        expect(pkg1.version, equals('1.2.3'));
        expect(pkg1.source, equals(PackageSource.hosted));

        const pathYaml = '''
packages:
  bar:
    description:
      path: "/local/bar"
    source: path
    version: "0.9.0"
''';
        final pkg2 = parsePackageFromYaml(pathYaml, 'bar');
        expect(pkg2, isNotNull);
        expect(pkg2!.source, equals(PackageSource.path));
        expect(pkg2.origin, equals('/local/bar'));

        const gitYaml = '''
packages:
  baz:
    description:
      url: "https://github.com/test/baz.git"
      ref: "feature"
      path: "sub/baz"
    source: git
    version: "2.1.0"
''';
        final pkg3 = parsePackageFromYaml(gitYaml, 'baz');
        expect(pkg3, isNotNull);
        expect(pkg3!.source, equals(PackageSource.git));
        expect(pkg3.origin, equals('https://github.com/test/baz.git'));
        expect(pkg3.gitRef, equals('feature'));
        expect(pkg3.gitPath, equals('sub/baz'));

        const customYaml = '''
packages:
  qux:
    description:
      name: qux
      url: "https://custom.pub.server"
    source: hosted
    version: "5.0.0"
''';
        final pkg4 = parsePackageFromYaml(customYaml, 'qux');
        expect(pkg4, isNotNull);
        expect(pkg4!.source, equals(PackageSource.customHosted));
        expect(pkg4.origin, equals('https://custom.pub.server'));
      },
    );

    test(
      'scanInstalledPackages reads packages from app-bundles directory',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'fix_globals_test_',
        );
        try {
          final appBundles = Directory(p.join(tempDir.path, 'app-bundles'));
          final pkgDir = Directory(p.join(appBundles.path, 'my_app'));
          await pkgDir.create(recursive: true);

          final lockFile = File(p.join(pkgDir.path, 'pubspec.lock'));
          await lockFile.writeAsString('''
packages:
  my_app:
    description:
      name: my_app
      url: "https://pub.dev"
    source: hosted
    version: "1.0.0"
''');

          final installed = scanInstalledPackages(tempDir);
          expect(installed.length, equals(1));
          expect(installed.first.name, equals('my_app'));
          expect(installed.first.version, equals('1.0.0'));
        } finally {
          await tempDir.delete(recursive: true);
        }
      },
    );

    test('handles cyclic symlinks without infinite recursion', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'fix_globals_symlink_',
      );
      try {
        final subDirA = Directory(p.join(tempDir.path, 'dirA'))..createSync();
        final subDirB = Directory(p.join(tempDir.path, 'dirA', 'dirB'))
          ..createSync();

        // Create circular symlink: dirA/dirB/linkToA -> dirA
        final link = Link(p.join(subDirB.path, 'linkToA'));
        try {
          link.createSync(subDirA.path);
        } catch (_) {
          // Windows might require elevated privileges for symlinks
        }

        // Should finish scanning without crashing or stack overflow
        final pkg = parsePackageFromDir(subDirA, 'non_existent');
        expect(pkg, isNull);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });

  group('fetchLatestVersion Network tests', () {
    test('fetches latest version from server', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        if (request.uri.path == '/api/packages/my_package') {
          request.response
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'latest': {'version': '2.5.0'},
              }),
            )
            ..close();
        } else {
          request.response
            ..statusCode = HttpStatus.notFound
            ..close();
        }
      });

      try {
        final registryUrl = 'http://${server.address.host}:${server.port}';
        final latest = await fetchLatestVersion('my_package', registryUrl);
        expect(latest, equals('2.5.0'));
      } finally {
        await server.close();
      }
    });

    test('returns null gracefully on timeout or HTTP error', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        // Deliberately hold request without responding
      });

      try {
        final registryUrl = 'http://${server.address.host}:${server.port}';
        final latest = await fetchLatestVersion(
          'my_package',
          registryUrl,
          timeout: const Duration(milliseconds: 100),
        );
        expect(latest, isNull);
      } finally {
        await server.close();
      }
    });
  });

  group('GlobalPackage Parser tests (pub global list text)', () {
    test('Parses hosted pub.dev packages correctly', () {
      final line = 'build_runner 2.15.0';
      final pkg = parsePubGlobalLine(line);

      expect(pkg, isNotNull);
      expect(pkg!.name, equals('build_runner'));
      expect(pkg.version, equals('2.15.0'));
      expect(pkg.source, equals(PackageSource.hosted));
      expect(pkg.origin, isNull);

      final actArgs = pkg.buildActivateArgs();
      expect(actArgs, equals(['install', 'build_runner', '--overwrite']));

      final actArgsUpdate = pkg.buildActivateArgs(update: true);
      expect(actArgsUpdate, equals(['install', 'build_runner', '--overwrite']));
    });

    test('Parses path packages correctly', () {
      final line = 'my_pkg 1.0.0 at path "/Users/merlyn/dev/my_pkg"';
      final pkg = parsePubGlobalLine(line);

      expect(pkg, isNotNull);
      expect(pkg!.name, equals('my_pkg'));
      expect(pkg.version, equals('1.0.0'));
      expect(pkg.source, equals(PackageSource.path));
      expect(pkg.origin, equals('/Users/merlyn/dev/my_pkg'));

      final actArgs = pkg.buildActivateArgs();
      expect(
        actArgs,
        equals([
          'install',
          'my_pkg@{path: /Users/merlyn/dev/my_pkg}',
          '--overwrite',
        ]),
      );
    });

    test('Parses path packages with single quotes or no quotes', () {
      final line1 = "my_pkg 1.0.0 at path '/Users/merlyn/dev/my_pkg'";
      final pkg1 = parsePubGlobalLine(line1);
      expect(pkg1!.origin, equals('/Users/merlyn/dev/my_pkg'));

      final line2 = 'my_pkg 1.0.0 at path /Users/merlyn/dev/my_pkg';
      final pkg2 = parsePubGlobalLine(line2);
      expect(pkg2!.origin, equals('/Users/merlyn/dev/my_pkg'));
    });

    test('Parses paths and git references containing spaces correctly', () {
      final line1 =
          'my_pkg 1.0.0 at path "/Users/merlyn/My Projects/Dart/my_pkg"';
      final pkg1 = parsePubGlobalLine(line1);
      expect(pkg1!.origin, equals('/Users/merlyn/My Projects/Dart/my_pkg'));

      final line2 =
          'my_git 1.2.3 from git "https://github.com/org/my git.git" at ref "main branch" at path "sub folder/pkg"';
      final pkg2 = parsePubGlobalLine(line2);
      expect(pkg2!.origin, equals('https://github.com/org/my git.git'));
      expect(pkg2.gitRef, equals('main branch'));
      expect(pkg2.gitPath, equals('sub folder/pkg'));
    });

    test('Parses simple git packages correctly', () {
      final line = 'my_git 1.2.3 from git "git@github.com:org/my_git.git"';
      final pkg = parsePubGlobalLine(line);

      expect(pkg, isNotNull);
      expect(pkg!.name, equals('my_git'));
      expect(pkg.version, equals('1.2.3'));
      expect(pkg.source, equals(PackageSource.git));
      expect(pkg.origin, equals('git@github.com:org/my_git.git'));
      expect(pkg.gitRef, isNull);
      expect(pkg.gitPath, isNull);

      final actArgs = pkg.buildActivateArgs();
      expect(
        actArgs,
        equals([
          'install',
          'my_git@{git: {url: git@github.com:org/my_git.git}}',
          '--overwrite',
        ]),
      );
    });

    test('Parses git packages with ref correctly', () {
      final line =
          'my_git 1.2.3 from git "git@github.com:org/my_git.git" at ref "main"';
      final pkg = parsePubGlobalLine(line);

      expect(pkg, isNotNull);
      expect(pkg!.name, equals('my_git'));
      expect(pkg.source, equals(PackageSource.git));
      expect(pkg.origin, equals('git@github.com:org/my_git.git'));
      expect(pkg.gitRef, equals('main'));
      expect(pkg.gitPath, isNull);

      final actArgs = pkg.buildActivateArgs();
      expect(
        actArgs,
        equals([
          'install',
          'my_git@{git: {url: git@github.com:org/my_git.git, ref: main}}',
          '--overwrite',
        ]),
      );
    });

    test('Parses git packages with path correctly', () {
      final line =
          'my_git 1.2.3 from git "git@github.com:org/my_git.git" at path "packages/my_git"';
      final pkg = parsePubGlobalLine(line);

      expect(pkg, isNotNull);
      expect(pkg!.name, equals('my_git'));
      expect(pkg.source, equals(PackageSource.git));
      expect(pkg.origin, equals('git@github.com:org/my_git.git'));
      expect(pkg.gitRef, isNull);
      expect(pkg.gitPath, equals('packages/my_git'));

      final actArgs = pkg.buildActivateArgs();
      expect(
        actArgs,
        equals([
          'install',
          'my_git@{git: {url: git@github.com:org/my_git.git, path: packages/my_git}}',
          '--overwrite',
        ]),
      );
    });

    test('Parses custom hosted packages correctly', () {
      final line = 'custom_tool 0.5.0 at hosted "https://onepub.dev"';
      final pkg = parsePubGlobalLine(line);

      expect(pkg, isNotNull);
      expect(pkg!.name, equals('custom_tool'));
      expect(pkg.version, equals('0.5.0'));
      expect(pkg.source, equals(PackageSource.customHosted));
      expect(pkg.origin, equals('https://onepub.dev'));

      final actArgs = pkg.buildActivateArgs();
      expect(
        actArgs,
        equals([
          'install',
          'custom_tool@{hosted: https://onepub.dev}',
          '--overwrite',
        ]),
      );
    });
  });
}
