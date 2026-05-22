import 'package:fix_globals/fix_globals.dart';
import 'package:test/test.dart';

void main() {
  group('GlobalPackage Parser tests', () {
    test('Parses hosted pub.dev packages correctly', () {
      final line = 'build_runner 2.15.0';
      final pkg = parsePubGlobalLine(line);

      expect(pkg, isNotNull);
      expect(pkg!.name, equals('build_runner'));
      expect(pkg.version, equals('2.15.0'));
      expect(pkg.source, equals(PackageSource.hosted));
      expect(pkg.origin, isNull);

      final actArgs = pkg.buildActivateArgs();
      expect(
        actArgs,
        equals(['pub', 'global', 'activate', 'build_runner', '--overwrite']),
      );
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
          'pub',
          'global',
          'activate',
          '--source',
          'path',
          '/Users/merlyn/dev/my_pkg',
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
          'pub',
          'global',
          'activate',
          '--source',
          'git',
          'git@github.com:org/my_git.git',
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
          'pub',
          'global',
          'activate',
          '--source',
          'git',
          'git@github.com:org/my_git.git',
          '--git-ref',
          'main',
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
          'pub',
          'global',
          'activate',
          '--source',
          'git',
          'git@github.com:org/my_git.git',
          '--git-path',
          'packages/my_git',
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
          'pub',
          'global',
          'activate',
          '--source',
          'hosted',
          '--hosted-url',
          'https://onepub.dev',
          'custom_tool',
          '--overwrite',
        ]),
      );
    });
  });
}
