// Copyright (c) 2026 Freya. All rights reserved.
import 'package:flutter/material.dart';
import 'package:freya_pdf/core/security/root_detection.dart';

/// Full-screen gate shown at startup when the device is detected as rooted
/// (Android) or jailbroken (iOS).
///
/// Rationale: FreyaPDF is a security-focused reader whose core promise is the
/// AES-256-GCM encrypted Secure Folder. A rooted/jailbroken device can bypass
/// in-app locks and dump keys, so we refuse to run on such a device rather
/// than gate only the unlock screen (which a root can trivially bypass).
///
/// The check is deliberately non-blocking and non-crashing:
/// - Debug builds always pass (emulators are "rooted" by default).
/// - If the plugin is unavailable or throws, the gate passes (unknown → safe).
/// - Only a *confirmed* compromised device in a release build shows the block.
class RootSecurityGate extends StatefulWidget {
  final Widget child;

  const RootSecurityGate({super.key, required this.child});

  @override
  State<RootSecurityGate> createState() => _RootSecurityGateState();
}

class _RootSecurityGateState extends State<RootSecurityGate> {
  bool _checking = true;
  bool _blocked = false;

  @override
  void initState() {
    super.initState();
    _runCheck();
  }

  Future<void> _runCheck() async {
    // This guard runs off the platform channel after the first frame; a short
    // delay keeps the splash smooth but does not gate UX on plugin speed.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      RootCheckOutcome outcome;
      try {
        outcome = await RootDetector.check();
      } catch (_) {
        // Never crash the app on the security gate; treat errors as clean.
        outcome = RootCheckOutcome.clean;
      }
      if (!mounted) return;
      setState(() {
        _blocked = outcome == RootCheckOutcome.compromised;
        _checking = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      // Brief blank splash while the (fast) check runs.
      return const SizedBox.shrink();
    }
    if (_blocked) {
      return const _BlockedDeviceScreen();
    }
    return widget.child;
  }
}

/// Message shown on a compromised device.
class _BlockedDeviceScreen extends StatelessWidget {
  const _BlockedDeviceScreen();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final bg = brightness == Brightness.dark
        ? colorScheme.surface
        : const Color(0xFFF8F9FA);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: colorScheme.error.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.gpp_bad_rounded,
                    size: 34,
                    color: colorScheme.error,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Unsupported device',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'FreyaPDF detected that this device is rooted or jailbroken. '
                  'Unsigned operating systems can bypass the encryption that '
                  'protects your PDFs, so the app is locked for your safety.',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 14,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    // No in-app bypass: guide the user to a supported device.
                  },
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('App locked'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
