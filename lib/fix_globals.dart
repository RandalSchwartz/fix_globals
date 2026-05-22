import 'dart:convert';
import 'dart:io';

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
    return ['pub', 'global', 'deactivate', name];
  }

  /// Builds the arguments list to activate this package.
  List<String> buildActivateArgs() {
    switch (source) {
      case PackageSource.hosted:
        return ['pub', 'global', 'activate', name, '--overwrite'];
      case PackageSource.path:
        return [
          'pub',
          'global',
          'activate',
          '--source',
          'path',
          origin!,
          '--overwrite',
        ];
      case PackageSource.git:
        final args = ['pub', 'global', 'activate', '--source', 'git', origin!];
        if (gitRef != null) {
          args.addAll(['--git-ref', gitRef!]);
        }
        if (gitPath != null) {
          args.addAll(['--git-path', gitPath!]);
        }
        args.add('--overwrite');
        return args;
      case PackageSource.customHosted:
        return [
          'pub',
          'global',
          'activate',
          '--source',
          'hosted',
          '--hosted-url',
          origin!,
          name,
          '--overwrite',
        ];
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

/// Parses a single line from `pub global list` output.
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
    // Format: from git "url" or from git "url" at path "sub_dir" or from git "url" at ref "main"
    final gitMatch = RegExp(
      r'''^from git\s+["']?([^"']+)["']?(.*)$''',
    ).firstMatch(remaining);
    if (gitMatch != null) {
      final url = gitMatch.group(1)!;
      final extra = gitMatch.group(2)?.trim() ?? '';

      String? ref;
      String? subPath;

      if (extra.isNotEmpty) {
        // Try parsing ref: at ref "main" or ref "main"
        final refMatch = RegExp(
          r'''(?:at\s+)?ref\s+["']?([^"']+)["']?''',
        ).firstMatch(extra);
        if (refMatch != null) {
          ref = refMatch.group(1);
        }

        // Try parsing path: at path "sub_dir" or path "sub_dir"
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
