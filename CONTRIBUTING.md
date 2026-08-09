# Contributing to Feya PDF

Thanks for your interest in contributing! Feya PDF is a private, commercial
project, but small contributions that respect the project's privacy and
security posture are welcome.

## Development setup

1. Install Flutter 3.x and an Android SDK.
2. Clone the repository.
3. `flutter pub get`
4. Run the checks: `flutter analyze && flutter test --concurrency=1`

## Before you start

- **Open an issue first** for any non-trivial change so we can agree on the
  approach before you write code.
- Keep changes **small and focused** — one feature or fix per PR.

## Code standards

- Follow the existing architecture: **Provider / ChangeNotifier** state, clean
  layering (presentation → providers → services → storage).
- Never add secrets to the repository, logs, or `SharedPreferences`.
- Handle **large files** carefully — never read a whole PDF into memory on the
  main isolate.
- Run `flutter analyze` — the analyzer must be clean.

## Testing

- Add or update tests for any behavior change.
- Prefer the existing test patterns (service unit tests, provider tests,
  widget tests). See `test/`.
- The full suite must pass:
  ```bash
  flutter test --concurrency=1
  ```

## Pull request process

1. Branch from `master`: `git checkout -b feat/my-change`
2. Implement + test your change.
3. Run `flutter analyze` and the full test suite.
4. Open a PR describing the problem, the change, and how it was verified.

## Do not

- Do not change version numbers or release metadata unless asked.
- Do not remove the embedded git-hash build flow (`tool/build_apk.sh`).
- Do not introduce data collection, analytics, or telemetry.
