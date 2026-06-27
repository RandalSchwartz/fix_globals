# Checklist: Publishing `fix_globals` to pub.dev

This checklist outlines all the steps and files required to transition `fix_globals` from a local project into a polished, high-scoring package on [pub.dev](https://pub.dev).

---

## 1. Metadata & `pubspec.yaml`
To publish successfully and maximize your **Pub Points** (up to 140/140), your `pubspec.yaml` needs to include standard descriptive metadata:

- [ ] **Check Name Uniqueness**: Confirm that the name `fix_globals` is not already taken on [pub.dev](https://pub.dev). If it is, consider a prefix/suffix like `puro_fix_globals` or similar.
- [ ] **Description**: Add a detailed description (between 60 and 180 characters) explaining what the package does.
- [ ] **Repository Link**: Add a `repository` field pointing to your GitHub repository (e.g., `https://github.com/username/fix_globals`).
- [ ] **Issue Tracker Link**: Add an `issue_tracker` field pointing to your repository's issues page (e.g., `https://github.com/username/fix_globals/issues`).
- [ ] **Homepage Link**: (Optional) Add a `homepage` link if you have a dedicated site.

*Example updated `pubspec.yaml` block:*
```yaml
name: fix_globals
description: A command-line utility to cleanly reinstall and refresh all globally activated Dart and Flutter packages from their original sources (pub, path, git, and custom registries).
version: 1.0.0
repository: https://github.com/your-github-username/fix_globals
issue_tracker: https://github.com/your-github-username/fix_globals/issues
```

---

## 2. Essential Files
These three files are mandatory for any pub.dev package and must reside in the root directory:

- [ ] **`LICENSE`**: Include a standard open-source license.
  > [!TIP]
  > The Dart team recommends using the **BSD 3-Clause License** for ecosystem consistency, but **MIT** or **Apache 2.0** are also very common and fully supported.
- [ ] **`README.md`**: Update the README with:
  - A brief introduction.
  - Clear installation instructions (using `dart pub global activate`).
  - Usage examples (with CLI arguments described).
  - Feature highlights.
- [ ] **`CHANGELOG.md`**: Update with details of the initial release:
  ```markdown
  ## 1.0.0
  - Initial release of `fix_globals`.
  - Supports re-activating packages from pub.dev, Git, local Path, and custom hosted registries.
  - Supports dry-run and choosing between Dart and Flutter SDK execution.
  ```

---

## 3. Best Practices & Bonus Points
- [ ] **Create an `example/` folder**: Add a small example folder containing a demo usage of the package, or in our case, a small markdown walkthrough explaining the CLI usage since it is a CLI-only tool. (Pub.dev parses the `example` folder to display a dedicated "Example" tab, which earns pub points!).
- [ ] **API Documentation**: Use triple-slash doc comments (`///`) on your public classes, methods, and functions in `lib/fix_globals.dart` (which we've already done!). Pub.dev automatically generates API documentation from these comments.

---

## 4. Housekeeping & Local Audits
Before executing the publish command, verify code health using these commands:

- [ ] **`dart format .`**: Ensure all code is 100% formatted.
- [ ] **`dart analyze`**: Confirm there are absolutely 0 warnings, lints, or info messages.
- [ ] **`dart test`**: Run the test suite and verify all tests pass.
- [ ] **Verify Ignores**: Confirm `.gitignore` or a `.pubignore` file is set up so that `.dart_tool/`, `.idea/`, or other build/IDE configurations are not packaged.

---

## 5. Dry Run Verification
Run the dry-run command to have `pub` analyze your package structure and report any issues or missing requirements:

- [ ] Run **Dry-Run**:
  ```bash
  dart pub publish --dry-run
  ```
- [ ] **Address warnings**: If the dry run spits out any warnings, resolve them before proceeding.

---

## 6. Uploading to pub.dev
> [!WARNING]
> Publishing is **permanent** and versions cannot be deleted. Always double-check your code before this step.

- [ ] **Authenticate**: Authenticate your terminal with your Google Account:
  ```bash
  dart pub login
  ```
- [ ] **Publish**: Run the final publish command:
  ```bash
  dart pub publish
  ```
  - Follow the terminal prompt to complete the publishing process.

---

## 7. Becoming a Verified Publisher (Optional)
To replace the `unverified uploader` label with a verified domain icon and blue shield badge, associate your package with a domain you own:

### Step 1: Verify Your Domain in Google Search Console
1. Go to the [Google Search Console](https://search.google.com/search-console).
2. Add your domain name (e.g., `stonehenge.com` or `randalschwartz.com`) as a new property.
3. Verify ownership of your domain (typically by adding a DNS TXT record provided by Google).

### Step 2: Create Your Verified Publisher Account
1. Sign in to [pub.dev](https://pub.dev) using your Google Account.
2. Click your user avatar in the top-right corner and select **Create Publisher**.
3. Enter your verified domain name and click **Create Publisher**.

### Step 3: Transfer your Package to the Publisher
1. Go to your live package page: [https://pub.dev/packages/fix_globals](https://pub.dev/packages/fix_globals).
2. Click on the **Admin** tab.
3. Under **Transfer to Publisher**, enter your verified publisher domain.
4. Click **Transfer to Publisher** (this is permanent and secure).

