import 'dart:async';
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
        // Note: If the Dart SDK someday provides a way to detect whether the package
        // was installed with a pinned version constraint, respect it here instead
        // of always falling back to installing the latest version.
        return name;
      case PackageSource.customHosted:
        return "$name@{hosted: $origin}";
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
        final mapStr = gitMap.entries
            .map((e) => "${e.key}: ${e.value}")
            .join(', ');
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
Directory getDartInstallDir({Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  final home = env['HOME'] ?? env['USERPROFILE'];
  if (home == null || home.isEmpty) {
    throw StateError(
      'Unable to determine home directory. Neither HOME nor USERPROFILE environment variable is set.',
    );
  }
  if (Platform.isMacOS) {
    return Directory(
      p.join(home, 'Library', 'Application Support', 'Dart', 'install'),
    );
  } else if (Platform.isWindows) {
    final localAppData =
        env['LOCALAPPDATA'] ?? p.join(home, 'AppData', 'Local');
    return Directory(p.join(localAppData, 'Dart', 'install'));
  } else {
    // Linux
    final xdgData = env['XDG_DATA_HOME'] ?? p.join(home, '.local', 'share');
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
    return parsePackageFromYaml(content, name);
  } catch (_) {
    return null;
  }
}

/// Parses the YAML content of a pubspec.lock file for package [name].
GlobalPackage? parsePackageFromYaml(String content, String name) {
  try {
    final doc = loadYaml(content);
    if (doc is! YamlMap) return null;

    final pkgs = doc['packages'];
    if (pkgs is! YamlMap) return null;

    final entry = pkgs[name];
    if (entry is! YamlMap) return null;

    final version = entry['version']?.toString() ?? '0.0.0';
    final sourceStr = entry['source']?.toString();
    final desc = entry['description'];

    if (desc is! YamlMap) return null;

    return switch (sourceStr) {
      'path' => GlobalPackage(
        name: name,
        version: version,
        source: PackageSource.path,
        origin: desc['path']?.toString(),
      ),
      'git' => GlobalPackage(
        name: name,
        version: version,
        source: PackageSource.git,
        origin: desc['url']?.toString(),
        gitRef: desc['ref']?.toString(),
        gitPath: desc['path']?.toString(),
      ),
      'hosted' => _parseHostedPackage(name, version, desc),
      _ => null,
    };
  } catch (_) {
    return null;
  }
}

GlobalPackage _parseHostedPackage(String name, String version, YamlMap desc) {
  final url = desc['url']?.toString();
  if (url != null &&
      url != 'https://pub.dev' &&
      url != 'https://pub.dartlang.org') {
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

void _findLockFiles(Directory dir, List<File> results, [Set<String>? visited]) {
  visited ??= <String>{};
  String canonicalPath;
  try {
    canonicalPath = dir.resolveSymbolicLinksSync();
  } catch (_) {
    canonicalPath = dir.path;
  }
  if (!visited.add(canonicalPath)) {
    return; // Prevent infinite loop on circular symlinks
  }
  try {
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is Directory) {
        _findLockFiles(entity, results, visited);
      } else if (entity is File && p.basename(entity.path) == 'pubspec.lock') {
        results.add(entity);
      }
    }
  } catch (_) {
    // Ignore unreadable subdirectories
  }
}

// Top-level cached regular expressions for string parsing
final _spaceRegExp = RegExp(r'\s+');
final _pathRegExp = RegExp(r'''^at path\s+["']?([^"']+)["']?$''');
final _hostedRegExp = RegExp(r'''^at hosted\s+["']?([^"']+)["']?$''');
final _gitRegExp = RegExp(r'''^from git\s+["']?([^"']+)["']?(.*)$''');
final _refRegExp = RegExp(r'''(?:at\s+)?ref\s+["']?([^"']+)["']?''');
final _gitPathRegExp = RegExp(r'''(?:at\s+)?path\s+["']?([^"']+)["']?''');

/// Parses a single line from traditional `pub global list` output (useful for tests and backward compatibility).
GlobalPackage? parsePubGlobalLine(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return null;

  final parts = trimmed.split(_spaceRegExp);
  if (parts.length < 2) return null;

  final name = parts[0];
  final version = parts[1];

  if (parts.length == 2) {
    return GlobalPackage(
      name: name,
      version: version,
      source: PackageSource.hosted,
    );
  }

  final remaining = parts.sublist(2).join(' ');
  return _parsePubGlobalRemaining(name, version, remaining) ??
      GlobalPackage(name: name, version: version, source: PackageSource.hosted);
}

GlobalPackage? _parsePubGlobalRemaining(
  String name,
  String version,
  String remaining,
) {
  final pathMatch = _pathRegExp.firstMatch(remaining);
  if (pathMatch != null) {
    return GlobalPackage(
      name: name,
      version: version,
      source: PackageSource.path,
      origin: pathMatch.group(1),
    );
  }

  final hostedMatch = _hostedRegExp.firstMatch(remaining);
  if (hostedMatch != null) {
    return GlobalPackage(
      name: name,
      version: version,
      source: PackageSource.customHosted,
      origin: hostedMatch.group(1),
    );
  }

  final gitMatch = _gitRegExp.firstMatch(remaining);
  if (gitMatch != null) {
    return _parseGitPackage(name, version, gitMatch);
  }

  return null;
}

GlobalPackage _parseGitPackage(String name, String version, Match gitMatch) {
  final url = gitMatch.group(1)!;
  final extra = gitMatch.group(2)?.trim() ?? '';

  String? ref;
  String? subPath;

  if (extra.isNotEmpty) {
    final refMatch = _refRegExp.firstMatch(extra);
    if (refMatch != null) {
      ref = refMatch.group(1);
    }

    final pathInGitMatch = _gitPathRegExp.firstMatch(extra);
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

/// Fetches the latest version of a package from the pub registry.
///
/// Encodes [packageName] safely to prevent malformed URI queries.
/// An existing [client] can be supplied for HTTP connection pooling; if omitted,
/// a temporary [HttpClient] is created and automatically closed.
/// Network errors, timeouts, and non-200 HTTP responses can be captured via [onDiagnostic].
Future<String?> fetchLatestVersion(
  String packageName,
  String registryUrl, {
  HttpClient? client,
  Duration timeout = const Duration(seconds: 10),
  void Function(String message)? onDiagnostic,
}) async {
  final httpClient = client ?? (HttpClient()..connectionTimeout = timeout);
  try {
    final encodedName = Uri.encodeComponent(packageName);
    final normalizedRegistry = registryUrl.endsWith('/')
        ? registryUrl.substring(0, registryUrl.length - 1)
        : registryUrl;
    final uri = Uri.parse('$normalizedRegistry/api/packages/$encodedName');
    if (uri.scheme == 'http' &&
        uri.host != 'localhost' &&
        uri.host != '127.0.0.1') {
      onDiagnostic?.call(
        'Warning: Registry "$registryUrl" uses insecure HTTP instead of HTTPS.',
      );
    }
    final request = await httpClient.getUrl(uri).timeout(timeout);
    final response = await request.close().timeout(timeout);
    if (response.statusCode == 200) {
      final content = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      final json = jsonDecode(content);
      if (json is Map) {
        return json['latest']?['version']?.toString();
      } else {
        onDiagnostic?.call('Unexpected JSON response for $packageName');
      }
    } else {
      onDiagnostic?.call(
        'HTTP ${response.statusCode} (${response.reasonPhrase}) while fetching version for $packageName',
      );
    }
  } on TimeoutException {
    onDiagnostic?.call(
      'Request timed out while fetching version for $packageName',
    );
  } on SocketException catch (e) {
    onDiagnostic?.call('Network/socket error for $packageName: ${e.message}');
  } on HttpException catch (e) {
    onDiagnostic?.call('HTTP error for $packageName: ${e.message}');
  } on FormatException catch (e) {
    onDiagnostic?.call('Format/parsing error for $packageName: ${e.message}');
  } catch (e) {
    onDiagnostic?.call('Error fetching version for $packageName: $e');
  } finally {
    if (client == null) {
      httpClient.close();
    }
  }
  return null;
}
