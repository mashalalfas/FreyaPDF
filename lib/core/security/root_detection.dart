// Copyright (c) 2026 Freya. All rights reserved.
import 'package:flutter/foundation.dart';
import 'package:flutter_jailbreak_detection_plus/flutter_jailbreak_detection_plus.dart';

/// Outcome of a root/jailbreak check.
enum RootCheckOutcome {
  /// The device shows no signs of rooting / jailbreaking.
  ///
  /// Also the result of a debug build or an unknown/errored plugin state, so
  /// legitimate users are never locked out by an unavailable check.
  clean,

  /// The device is rooted (Android) or jailbroken (iOS).
  compromised,
}

/// Wrapper around `flutter_jailbreak_detection` that is always exception-safe.
///
/// The plugin uses RootBeer on Android and IOSSecuritySuite on iOS. It requires
/// no manifest changes on either platform. Calls through the MethodChannel can
/// still throw (e.g. platform not supported, or during widget tests), so every
/// path here degrades safely to a non-blocking outcome rather than crashing.
class RootDetector {
  const RootDetector._();

  /// Check whether the device is rooted/jailbroken. Never throws.
  ///
  /// - Debug builds (`kDebugMode`) always report [RootCheckOutcome.clean] so
  ///   development on emulators — which are often "rooted" by default — is not
  ///   blocked by the startup safety gate.
  /// - Any platform/plugin error degrades to [RootCheckOutcome.clean] (safe-by-
  ///   default), never a crash.
  static Future<RootCheckOutcome> check() async {
    if (kDebugMode) {
      // Emulators ship with an unlocked bootloader / adb root; forcing the
      // gate to block would break development. Enforce this in release only.
      return RootCheckOutcome.clean;
    }

    try {
      final jailbroken = await FlutterJailbreakDetectionPlus.jailbroken;
      return jailbroken
          ? RootCheckOutcome.compromised
          : RootCheckOutcome.clean;
    } catch (_) {
      // Plugin unavailable / channel error in a release build. Do not brick
      // the device; allow the app to run.
      return RootCheckOutcome.clean;
    }
  }
}
