import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// The source from which a global package was activated.
enum PackageSource { hosted, path, git, customHosted }

/// Represents a globally activated Dart package.
class GlobalPackage {
  final String name;
  final String version;
  final PackageSource source;
  final String? origin;
  final String? gitRef;
  final String? gitPath;

  GlobalPackage({
    required this.name,
    required this.version,
    required this.source,
    this.origin,
    this.gitRef,
    this.gitPath,
  });

  /// Builds the arguments list to deactivate this package.
  List<String> buildDeactivateArgs() {
    return ['uninstall', name];
  }

  /// Builds the arguments list to activate this package.
  List<String> buildActivateArgs({bool update = false}) {
    final descriptor = buildDescriptor(update: update);
    return ['install', descriptor, '--overwrite'];
  }

  /// Reconstructs the package descriptor for `dart install <package>[@<descriptor>]`.
  String buildDescriptor({bool update = false}) {
    switch (source) {
      case PackageSource.hosted:
        if (update) return name;
        return '$name@$version';
      case PackageSource.customHosted:
        if (update) {
          return "$name@{hosted: $origin}";
        }
        return "$name@{hosted: $origin, version: $version}";
      case PackageSource.path:
        return "$name@{path: $origin}";
      case PackageSource.git:
        final gitMap = <String, String>{};
        gitMap['url'] = origin!;
        if (gitRef != null) {
          gitMap['ref'] = gitRef!;
        }
        if (gitPath != null) {
          gitMap['path'] = gitPath!;
        }
        final mapStr = gitMap.entries.map((e) => "${e.key}: ${e.value}").join(', ');
        return "$name@{git: {$mapStr}}";
    }
  }

  @override
  String toString() {
    final sb = StringBuffer('$name $version');
    switch (source) {
      case PackageSource.hosted:
        break;
      case PackageSource.path:
        sb.write(' at path "$origin"');
        break;
      case PackageSource.git:
        sb.write(' from git "$origin"');
        if (gitRef != null) sb.write(' ref "$gitRef"');
        if (gitPath != null) sb.write(' path "$gitPath"');
        break;
      case PackageSource.customHosted:
        sb.write(' at hosted "$origin"');
        break;
    }
    return sb.toString();
  }
}

/// Resolves the platform-specific Dart install directory.
Directory getDartInstallDir() {
  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (Platform.isMacOS) {
    return Directory(p.join(home!, 'Library', 'Application Support', 'Dart', 'install'));
  } else if (Platform.isWindows) {
    final localAppData = Platform.environment['LOCALAPPDATA'] ?? p.join(home!, 'AppData', 'Local');
    return Directory(p.join(localAppData, 'Dart', 'install'));
  } else {
    // Linux
    final xdgData = Platform.environment['XDG_DATA_HOME'] ?? p.join(home!, '.local', 'share');
    return Directory(p.join(xdgData, 'dart', 'install'));
  }
}

/// Scans the Dart install directory to find all globally installed packages.
List<GlobalPackage> scanInstalledPackages(Directory installDir) {
  final appBundlesDir = Directory(p.join(installDir.path, 'app-bundles'));
  if (!appBundlesDir.existsSync()) {
    return [];
  }

  final packages = <GlobalPackage>[];
  for (final entity in appBundlesDir.listSync()) {
    if (entity is Directory) {
      final name = p.basename(entity.path);
      final pkg = parsePackageFromDir(entity, name);
      if (pkg != null) {
        packages.add(pkg);
      }
    }
  }
  return packages;
}

/// Parses the package description from a package's installation directory by looking at its pubspec.lock.
GlobalPackage? parsePackageFromDir(Directory packageDir, String name) {
  final lockFiles = <File>[];
  try {
    _findLockFiles(packageDir, lockFiles);
  } catch (_) {
    return null;
  }

  if (lockFiles.isEmpty) return null;

  final lockFile = lockFiles.first;
  try {
    final content = lockFile.readAsStringSync();
    final doc = loadYaml(content);
    if (doc is YamlMap && doc.containsKey('packages')) {
      final pkgs = doc['packages'];
      if (pkgs is YamlMap && pkgs.containsKey(name)) {
        final entry = pkgs[name];
        if (entry is YamlMap) {
          final version = entry['version']?.toString() ?? '0.0.0';
          final sourceStr = entry['source']?.toString();
          final desc = entry['description'];

          if (sourceStr == 'path' && desc is YamlMap) {
            final path = desc['path']?.toString();
            return GlobalPackage(
              name: name,
              version: version,
              source: PackageSource.path,
              origin: path,
            );
          } else if (sourceStr == 'git' && desc is YamlMap) {
            final url = desc['url']?.toString();
            final ref = desc['ref']?.toString();
            final path = desc['path']?.toString();
            return GlobalPackage(
              name: name,
              version: version,
              source: PackageSource.git,
              origin: url,
              gitRef: ref,
              gitPath: path,
            );
          } else if (sourceStr == 'hosted' && desc is YamlMap) {
            final url = desc['url']?.toString();
            if (url != null && url != 'https://pub.dev' && url != 'https://pub.dartlang.org') {
              return GlobalPackage(
                name: name,
                version: version,
                source: PackageSource.customHosted,
                origin: url,
              );
            }
            return GlobalPackage(
              name: name,
              version: version,
              source: PackageSource.hosted,
            );
          }
        }
      }
    }
  } catch (_) {
    // Ignore error and return null
  }
  return null;
}

void _findLockFiles(Directory dir, List<File> results) {
  for (final entity in dir.listSync()) {
    if (entity is Directory) {
      _findLockFiles(entity, results);
    } else if (entity is File && p.basename(entity.path) == 'pubspec.lock') {
      results.add(entity);
    }
  }
}

/// Parses a single line from traditional `pub global list` output (useful for tests and backward compatibility).
GlobalPackage? parsePubGlobalLine(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return null;

  final parts = trimmed.split(RegExp(r'\s+'));
  if (parts.length < 2) return null;

  final name = parts[0];
  final version = parts[1];

  if (parts.length > 2) {
    final remaining = parts.sublist(2).join(' ');

    // 1. Path Match
    final pathMatch = RegExp(
      r'''^at path\s+["']?([^"']+)["']?$''',
    ).firstMatch(remaining);
    if (pathMatch != null) {
      return GlobalPackage(
        name: name,
        version: version,
        source: PackageSource.path,
        origin: pathMatch.group(1),
      );
    }

    // 2. Custom Hosted Match
    final hostedMatch = RegExp(
      r'''^at hosted\s+["']?([^"']+)["']?$''',
    ).firstMatch(remaining);
    if (hostedMatch != null) {
      return GlobalPackage(
        name: name,
        version: version,
        source: PackageSource.customHosted,
        origin: hostedMatch.group(1),
      );
    }

    // 3. Git Match (could contain optional ref or sub-path)
    final gitMatch = RegExp(
      r'''^from git\s+["']?([^"']+)["']?(.*)$''',
    ).firstMatch(remaining);
    if (gitMatch != null) {
      final url = gitMatch.group(1)!;
      final extra = gitMatch.group(2)?.trim() ?? '';

      String? ref;
      String? subPath;

      if (extra.isNotEmpty) {
        final refMatch = RegExp(
          r'''(?:at\s+)?ref\s+["']?([^"']+)["']?''',
        ).firstMatch(extra);
        if (refMatch != null) {
          ref = refMatch.group(1);
        }

        final pathInGitMatch = RegExp(
          r'''(?:at\s+)?path\s+["']?([^"']+)["']?''',
        ).firstMatch(extra);
        if (pathInGitMatch != null) {
          subPath = pathInGitMatch.group(1);
        }
      }

      return GlobalPackage(
        name: name,
        version: version,
        source: PackageSource.git,
        origin: url,
        gitRef: ref,
        gitPath: subPath,
      );
    }
  }

  // Default to hosted on pub.dev
  return GlobalPackage(
    name: name,
    version: version,
    source: PackageSource.hosted,
  );
}

/// Executes a shell command synchronously and returns the output/exit code.
ProcessResult runCommand(String command, List<String> args) {
  return Process.runSync(
    command,
    args,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
}
