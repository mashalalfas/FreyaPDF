# Plan 004: Add CI/CD pipeline (GitHub Actions)

> **Executor instructions**: Follow step by step. Verify each step before moving on. If any STOP condition, stop and report.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: dx
- **Planned at**: commit `8a85841`, 2026-06-13

## Why this matters

71 tests exist but run only on demand. A CI pipeline catches regressions before merge. This is cheap insurance for a project with encryption and file I/O.

## Steps

### Step 1: Create `.github/workflows/ci.yml`

```yaml
name: CI

on:
  push:
    branches: [ master ]
  pull_request:
    branches: [ master ]

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.x'
      - run: flutter pub get
      - run: dart analyze

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.x'
      - run: flutter pub get
      - run: flutter test --exclude-tags=slow
```

### Step 2: Tag the slow encryption test

In `test/encryption_service_test.dart`, add a `@Tags(['slow'])` annotation to the 1MB round-trip test so it's excluded from CI (but still runnable locally).

Find the test `'large payload (1MB random data) round-trips correctly'` and prepend:
```dart
@Tags(['slow'])
test('large payload (1MB random data) round-trips correctly', () {
```

Import at top: `import 'package:test/test.dart' show Tags;` (if not already imported in the test file)

### Step 3: Run the fast tests only

```bash
flutter test --exclude-tags=slow
```
Expected: all non-slow tests pass.

### Step 4: Final verification

```bash
dart analyze
```
0 issues.

## Done criteria

- [ ] `.github/workflows/ci.yml` exists with analyze + test jobs
- [ ] `test/encryption_service_test.dart` has `@Tags(['slow'])` on the 1MB test
- [ ] `dart analyze` exits 0
- [ ] `flutter test --exclude-tags=slow` passes
- [ ] `flutter test test/encryption_service_test.dart --tags=slow` still passes (the test works, just slow)

## STOP conditions

- If `.github/` already exists and has workflows, merge rather than overwrite
