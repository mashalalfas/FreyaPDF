// Copyright (c) 2026 Freya. All rights reserved.
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:freya_pdf/features/encryption/encryption_provider.dart';
import 'package:freya_pdf/features/security/app_lock_service.dart';
import 'package:freya_pdf/features/security/biometric_passphrase_storage.dart';
import 'package:freya_pdf/features/settings/settings_provider.dart';

/// Full-screen lock overlay shown on cold start when app lock is enabled.
/// On successful PIN or biometric unlock, [child] is revealed via a fade.
class AppLockGate extends StatefulWidget {
  final Widget child;

  const AppLockGate({super.key, required this.child});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

/// The lifecycle states treated as "app went to background". Anything else
/// (notably [AppLifecycleState.inactive], triggered by the notification shade,
/// permission dialogs, split-screen, etc.) does NOT count as a return from
/// background.
///
/// Exposed top-level so the re-lock decision is unit-testable in isolation.
bool isBackgroundLifecycleState(AppLifecycleState state) =>
    state == AppLifecycleState.paused ||
    state == AppLifecycleState.hidden ||
    state == AppLifecycleState.detached;

/// Decide whether a lifecycle transition should re-trigger the lock screen.
/// True only when moving from a true background state back to resumed.
/// Notification-shade (inactive) cycles return false.
///
/// Exposed top-level for unit testing.
bool shouldRelockOnResume(AppLifecycleState previous, AppLifecycleState next) =>
    next == AppLifecycleState.resumed && isBackgroundLifecycleState(previous);

class _AppLockGateState extends State<AppLockGate>
    with WidgetsBindingObserver {
  final AppLockService _lockService = AppLockService();
  bool _locked = true;
  bool _biometricAvailable = false;
  bool _sawBackgroundState = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkLock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Track whether we have seen a true background state since the last
    // resume. Notification-shade or permission-dialog cycles only go through
    // [inactive], so we must not re-lock on those.
    if (isBackgroundLifecycleState(state)) {
      _sawBackgroundState = true;
    }
    final shouldRelock =
        state == AppLifecycleState.resumed && _sawBackgroundState;
    if (state == AppLifecycleState.resumed) {
      _sawBackgroundState = false;
    }
    if (shouldRelock) {
      _checkLock();
    }
  }

  Future<void> _checkLock() async {
    final settings = context.read<SettingsProvider>();
    if (!settings.appLockEnabled) {
      if (mounted) setState(() => _locked = false);
      return;
    }
    final bio = await _lockService.isBiometricUsable();
    final bioEnabled = await _lockService.getBiometricEnabled();
    if (mounted) {
      setState(() {
        _biometricAvailable = bio && bioEnabled;
        _locked = true;
      });
    }
    // Auto-attempt biometric whenever the lock screen appears (cold start AND
    // resume). PIN is only a fallback when no biometric hardware / enrolled
    // biometrics are available (or the user disabled biometrics). Defer the
    // system prompt until after the frame so the Android Activity is confirmed
    // resumed/focused before local_auth's BiometricPrompt tries to attach —
    // firing it during widget mount or the lifecycle transition silently
    // no-ops and the user never sees it.
    if (_biometricAvailable) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        // Ensure the Android Activity is fully resumed/focused before
        // local_auth's BiometricPrompt attaches. On some devices (e.g. HMD
        // Skyline) the next frame fires before the Activity is truly resumed
        // and the prompt silently no-ops, so wait a beat before firing.
        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
        var ok = await _lockService.authenticateWithBiometrics();
        if (ok && mounted) {
          setState(() => _locked = false);
          await _restoreEncryptionPassphrase();
          return;
        }
        // If the first attempt failed, retry ONCE after a short delay.
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        ok = await _lockService.authenticateWithBiometrics();
        if (ok && mounted) {
          setState(() => _locked = false);
          await _restoreEncryptionPassphrase();
        }
      });
    }
  }

  void _unlock() {
    setState(() => _locked = false);
    _restoreEncryptionPassphrase();
  }

  /// After a successful app-lock authentication, release the persisted
  /// encryption passphrase into [EncryptionProvider] only if the provider
  /// does not already have one. If app lock is disabled this path is never
  /// reached, so the passphrase is not silently restored.
  Future<void> _restoreEncryptionPassphrase() async {
    if (!mounted) return;
    final encryption = context.read<EncryptionProvider>();
    if (encryption.hasPassphrase) return;
    final stored = await BiometricPassphraseStorage().read();
    if (stored != null && stored.isNotEmpty) {
      encryption.setPassphrase(stored);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: _locked
          ? KeyedSubtree(
              key: const ValueKey('locked'),
              child: AppLockScreen(
                lockService: _lockService,
                biometricAvailable: _biometricAvailable,
                onUnlock: _unlock,
              ),
            )
          : KeyedSubtree(
              key: const ValueKey('unlocked'),
              child: widget.child,
            ),
    );
  }
}

/// PIN entry screen with numeric keypad and optional biometric fallback.
class AppLockScreen extends StatefulWidget {
  final AppLockService lockService;
  final bool biometricAvailable;
  final VoidCallback onUnlock;

  const AppLockScreen({
    super.key,
    required this.lockService,
    required this.biometricAvailable,
    required this.onUnlock,
  });

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

/// Decide whether the PIN buffer should auto-submit after adding [digit].
/// True when a stored length is known and the buffer has just reached it. For
/// legacy installs (no stored length) the buffer never auto-submits — the user
/// presses the manual confirm/check button instead.
///
/// Exposed top-level for unit testing.
bool shouldAutoSubmitPin(int bufferLength, int? storedPinLength) =>
    storedPinLength != null && bufferLength == storedPinLength;

class _AppLockScreenState extends State<AppLockScreen> {
  final _pinBuffer = <int>[];
  static const int _maxPinLength = 6;
  // The configured PIN length (4-6), or `null` for legacy installs where no
  // length was stored (fall back to a manual confirm/check button).
  int? _pinLength;
  String? _errorText;
  bool _shake = false;

  // Brute-force lockout surface: when non-null, the keypad is disabled and a
  // countdown is shown until [lockoutRemaining] reaches zero.
  Duration _lockoutRemaining = Duration.zero;
  Timer? _lockoutTimer;

  @override
  void initState() {
    super.initState();
    _initPinLength();
    _refreshLockout();
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    super.dispose();
  }

  /// Load the stored PIN length. Legacy installs (no stored length) leave
  /// [_pinLength] as `null`, which enables the manual confirm/check button and
  /// lets the user submit at 4, 5, or 6 digits.
  Future<void> _initPinLength() async {
    final stored = await widget.lockService.getPinLength();
    if (!mounted) return;
    setState(() => _pinLength = stored);
  }

  /// Whether the legacy confirm/check button should be shown: only when no
  /// stored length exists (legacy installs) or while the length is still being
  /// resolved. The user can submit whenever the buffer is 4-6 digits.
  bool get _useManualSubmit => _pinLength == null;

  /// Total number of dots shown. For the stored-length path this matches the
  /// configured length; for the legacy path we show a fixed 6 so the buffer
  /// never visually overflows.
  int get _dotCount => _pinLength ?? _maxPinLength;

  /// Refresh the lockout countdown from the service and, if still locked,
  /// schedule a re-check for one second later. Stops once the lock expires.
  Future<void> _refreshLockout() async {
    final remaining = await widget.lockService.getLockoutRemaining();
    if (!mounted) return;
    setState(() => _lockoutRemaining = remaining);
    _lockoutTimer?.cancel();
    if (remaining > Duration.zero) {
      _lockoutTimer = Timer(const Duration(seconds: 1), _refreshLockout);
    }
  }

  bool get _lockedOut => _lockoutRemaining > Duration.zero;

  void _onDigit(int digit) {
    if (_lockedOut) {
      HapticFeedback.selectionClick();
      return;
    }
    if (_pinBuffer.length >= _maxPinLength) return;
    HapticFeedback.lightImpact();
    setState(() {
      _pinBuffer.add(digit);
      _errorText = null;
    });
    // Auto-submit once the buffer reaches the stored length.
    if (shouldAutoSubmitPin(_pinBuffer.length, _pinLength)) {
      _verifyPin();
    }
  }

  void _onDelete() {
    if (_lockedOut || _pinBuffer.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pinBuffer.removeLast();
      _errorText = null;
    });
  }

  /// Verify current buffer. For the legacy path, a wrong attempt at 4 digits
  /// does NOT clear the buffer — it lets the user keep typing to 5 or 6 and
  /// try again — but the failed attempt still counts toward the brute-force
  /// lockout.
  Future<void> _verifyPin() async {
    if (_pinBuffer.length < 4) return;
    final pin = _pinBuffer.join();
    final wasManual = _useManualSubmit;
    final ok = await widget.lockService.verifyPin(pin);
    if (!mounted) return;
    if (ok) {
      HapticFeedback.heavyImpact();
      widget.onUnlock();
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _errorText = 'Incorrect PIN';
        _shake = true;
        // Legacy path: keep the buffer so the user can continue typing to a
        // longer length. Stored-length path: clear as before.
        if (!wasManual) {
          _pinBuffer.clear();
        }
      });
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      setState(() => _shake = false);
      // Engage the lockout countdown if the service has escalated.
      await _refreshLockout();
    }
  }

  Future<void> _onBiometric() async {
    final ok = await widget.lockService.authenticateWithBiometrics();
    if (ok && mounted) {
      widget.onUnlock();
    }
  }

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
        child: _shake
            ? _ShakeWidget(child: _buildBody(colorScheme))
            : _buildBody(colorScheme),
      ),
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(flex: 2),

        // App logo & title
        Image.asset(
          'assets/logo/FREYA PDF.png',
          width: 64,
          height: 64,
        ),
        const SizedBox(height: 20),
        Text(
          'Freya PDF',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          _lockedOut
              ? 'Too many attempts. Try again later.'
              : 'Enter your PIN to unlock',
          style: TextStyle(
            color: _lockedOut
                ? colorScheme.error
                : colorScheme.onSurfaceVariant,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 36),

        // PIN dots
        _PinDots(
          length: _dotCount,
          filledCount: min(_pinBuffer.length, _dotCount),
          error: _errorText != null,
          colorScheme: colorScheme,
        ),
        if (_errorText != null) ...[
          const SizedBox(height: 12),
          Text(
            _errorText!,
            style: TextStyle(
              color: colorScheme.error,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        if (_lockedOut) ...[
          const SizedBox(height: 12),
          Text(
            'Locked. Try again in ${_formatLockout(_lockoutRemaining)}.',
            style: TextStyle(
              color: colorScheme.error,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 12),

        // Legacy path only: no stored PIN length, so a manual confirm/check
        // lets the user submit at 4, 5, or 6 digits. Always visible (enabled
        // only when buffer has 4-6 digits) so the user knows how to submit.
        if (_useManualSubmit) ...[
          const SizedBox(height: 4),
          SizedBox(
            width: 220,
            child: FilledButton(
              onPressed:
                  (_pinBuffer.length >= 4 && !_lockedOut) ? _verifyPin : null,
              child: const Text('Check PIN'),
            ),
          ),
        ],

        // Biometric button. Always shown so the user knows fingerprint unlock
        // is an option; greyed out (disabled) when biometrics aren't
        // available/enrolled or the user disabled them, and while a lockout is
        // active.
        IconButton(
          icon: const Icon(Icons.fingerprint_rounded, size: 36),
          color: colorScheme.primary,
          onPressed:
              (widget.biometricAvailable && !_lockedOut) ? _onBiometric : null,
          tooltip: widget.biometricAvailable
              ? 'Unlock with biometrics'
              : 'Biometrics unavailable — use PIN',
        ),

        const Spacer(flex: 1),

        // Numeric keypad (disabled while locked out)
        _NumericKeypad(
          onDigit: _onDigit,
          onDelete: _onDelete,
          canDelete: _pinBuffer.isNotEmpty,
          colorScheme: colorScheme,
          disabled: _lockedOut,
        ),

        const Spacer(flex: 2),
      ],
    );
  }

  /// Format a [Duration] as either `SSs` or `m:SS` for the lockout countdown.
  String _formatLockout(Duration d) {
    final total = d.inSeconds;
    if (total < 60) return '${total}s';
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

/// Row of dots representing PIN digits entered.
class _PinDots extends StatelessWidget {
  final int length;
  final int filledCount;
  final bool error;
  final ColorScheme colorScheme;

  const _PinDots({
    required this.length,
    required this.filledCount,
    required this.error,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(length, (i) {
        final filled = i < filledCount;
        return Container(
          width: 14,
          height: 14,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: error
                ? colorScheme.error
                : filled
                    ? colorScheme.primary
                    : colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
          child: filled
              ? Center(
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                  ),
                )
              : null,
        );
      }),
    );
  }
}

/// Numeric keypad 1-9, 0, backspace.
class _NumericKeypad extends StatelessWidget {
  final void Function(int digit) onDigit;
  final VoidCallback onDelete;
  final bool canDelete;
  final ColorScheme colorScheme;
  final bool disabled;

  const _NumericKeypad({
    required this.onDigit,
    required this.onDelete,
    required this.canDelete,
    required this.colorScheme,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    const rows = [
      [1, 2, 3],
      [4, 5, 6],
      [7, 8, 9],
    ];
    return Column(
      children: [
        for (final row in rows) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: row.map((d) => _KeyButton(
                  label: '$d',
                  onTap: disabled ? null : () => onDigit(d),
                  disabled: disabled,
                )).toList(),
          ),
          const SizedBox(height: 12),
        ],
        // Bottom row: empty spacer, 0, backspace
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 76),
            _KeyButton(
              label: '0',
              onTap: disabled ? null : () => onDigit(0),
              disabled: disabled,
            ),
            _KeyButton(
              icon: Icons.backspace_outlined,
              onTap: (disabled || !canDelete) ? null : onDelete,
              disabled: disabled || !canDelete,
            ),
          ],
        ),
      ],
    );
  }
}

/// Single keypad button.
class _KeyButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool disabled;

  const _KeyButton({
    this.label,
    this.icon,
    this.onTap,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fg = disabled
        ? colorScheme.onSurface.withValues(alpha: 0.15)
        : colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: disabled ? null : onTap,
          child: Container(
            width: 76,
            height: 64,
            alignment: Alignment.center,
            child: label != null
                ? Text(
                    label!,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w500,
                      color: fg,
                    ),
                  )
                : Icon(icon, size: 26, color: fg),
          ),
        ),
      ),
    );
  }
}

/// Simple shake animation widget for incorrect PIN.
class _ShakeWidget extends StatefulWidget {
  final Widget child;
  const _ShakeWidget({required this.child});

  @override
  State<_ShakeWidget> createState() => _ShakeWidgetState();
}

class _ShakeWidgetState extends State<_ShakeWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _animation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: 10), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10, end: 8), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8, end: 6), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -6, end: 4), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -4, end: 2), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -2, end: 0), weight: 1),
    ]).animate(_controller);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_animation.value, 0),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
