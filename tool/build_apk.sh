#!/usr/bin/env bash
# Build a FeyaPDF APK with the current git commit hash embedded.
#
# Usage:
#   ./tool/build_apk.sh [release|profile|debug] [--install]
#
# The embedded commit is read by lib/build_info.dart via --dart-define=GIT_HASH
# and shown in Settings -> About -> Commit.
set -euo pipefail

cd "$(dirname "$0")/.."

MODE="${1:-release}"
INSTALL=false
if [[ "${2:-}" == "--install" ]]; then
  INSTALL=true
fi

# Resolve the Flutter binary (prefer the direct binary, then PATH).
if [[ -x /home/max/snap/flutter/common/flutter/bin/flutter ]]; then
  FLUTTER=/home/max/snap/flutter/common/flutter/bin/flutter
else
  FLUTTER="$(command -v flutter)"
fi

if [[ -z "$FLUTTER" ]]; then
  echo "error: flutter not found" >&2
  exit 1
fi

GIT_HASH="$(git rev-parse --short HEAD)"
echo "Building $MODE APK with GIT_HASH=$GIT_HASH"

"$FLUTTER" build apk --"$MODE" --dart-define="GIT_HASH=$GIT_HASH"

APK="build/app/outputs/flutter-apk/app-$MODE.apk"

if [[ "$INSTALL" == true ]]; then
  echo "Installing $APK on connected device..."
  adb install -r "$APK"
fi
