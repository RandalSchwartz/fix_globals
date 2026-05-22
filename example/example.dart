import 'package:fix_globals/fix_globals.dart';

void main() {
  // A raw line obtained from running 'dart pub global list'
  const gitLine =
      'melos 7.7.0 from git "https://github.com/invertase/melos.git" at ref "main"';

  print('Parsing line: "$gitLine"');

  // Parse the line using the library function
  final package = parsePubGlobalLine(gitLine);

  if (package != null) {
    print('\nSuccessfully parsed package:');
    print('  - Name:     ${package.name}');
    print('  - Version:  ${package.version}');
    print('  - Source:   ${package.source.name}');
    print('  - Origin:   ${package.origin}');
    print('  - Git Ref:  ${package.gitRef}');

    // Generate reactivation command arguments
    final activationArgs = package.buildActivateArgs();
    print('\nReactivation arguments:');
    print('  flutter ${activationArgs.join(' ')}');
  } else {
    print('Failed to parse package line.');
  }
}
