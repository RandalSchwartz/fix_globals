# Goal: `new_fix_globals` - Robust Global Package Reinstaller

We will implement a robust Dart-based CLI tool inside this directory (`/Users/merlyn/Projects/Dart/new_fix_globals`) to replace the simplified shell-based `/Users/merlyn/bin/fix-globals` script. The tool will correctly parse the output of `pub global list` and automatically handle re-activating packages from various sources (pub.dev, local path, git, and custom hosted registries) with the correct arguments.

## User Review Required

We are implementing this command directly inside `/Users/merlyn/Projects/Dart/new_fix_globals`. 

We will offer two main options:
1. `--dry-run` or `-n`: Print out the commands that would be executed without running them.
2. `--sdk` or `-s`: Choose between running the process using the `flutter` SDK or the `dart` SDK. Defaults to `flutter` if present, otherwise fallback to `dart`.

## Proposed Changes

### [MODIFY] [bin/new_fix_globals.dart](file:///Users/merlyn/Projects/Dart/new_fix_globals/bin/new_fix_globals.dart)
The main entry point will parse CLI options (using manual argument checking to keep dependencies minimal and compilation extremely fast) and run the execution flow.

### [MODIFY] [lib/new_fix_globals.dart](file:///Users/merlyn/Projects/Dart/new_fix_globals/lib/new_fix_globals.dart)
This will contain the core parser and shell command executors. 

#### Parsing Logic
Each line of `pub global list` will be parsed. We will identify:
* **Hosted**: `name version` (e.g. `build_runner 2.15.0`)
* **Path**: `name version at path "path"`
* **Git**: `name version from git "url"`
* **Custom Hosted**: `name version at hosted "url"`

For each, we will build the exact list of command tokens needed to run `pub global activate`.

## Verification Plan

We will test the code by compiling/running it locally and verifying that it successfully parses different kinds of package outputs.
- Running: `dart bin/new_fix_globals.dart --dry-run`
- Running: `dart bin/new_fix_globals.dart`
