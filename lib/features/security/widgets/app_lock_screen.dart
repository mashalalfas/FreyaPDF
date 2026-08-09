import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:freya_pdf/features/security/app_lock_service.dart';
import 'package:freya_pdf/features/settings/settings_provider.dart';

/// Full-screen lock overlay shown on cold start when app lock is enabled.
/// On successful PIN or biometric unlock, [child] is revealed via a fade.
class AppLockGate extends StatefulWidget {
  final Widget child;

  const AppLockGate({super.key, required this.child});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate>
    with WidgetsBindingObserver {
  final AppLockService _lockService = AppLockService();
  bool _locked = true;
  bool _biometricAvailable = false;

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
    // Re-lock when app returns from background
    if (state == AppLifecycleState.resumed) {
      _checkLock();
    }
  }

  Future<void> _checkLock() async {
    final settings = context.read<SettingsProvider>();
    if (!settings.appLockEnabled) {
      if (mounted) setState(() => _locked = false);
      return;
    }
    final bio = await _lockService.isBiometricAvailable();
    final bioEnabled = await _lockService.getBiometricEnabled();
    if (mounted) {
      setState(() {
        _biometricAvailable = bio && bioEnabled;
        _locked = true;
      });
    }
    // Auto-attempt biometric if available
    if (_biometricAvailable) {
      final ok = await _lockService.authenticateWithBiometrics();
      if (ok && mounted) {
        setState(() => _locked = false);
      }
    }
  }

  void _unlock() {
    setState(() => _locked = false);
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

class _AppLockScreenState extends State<AppLockScreen> {
  final _pinBuffer = <int>[];
  static const int _pinLength = 6;
  String? _errorText;
  bool _shake = false;

  void _onDigit(int digit) {
    if (_pinBuffer.length >= _pinLength) return;
    HapticFeedback.lightImpact();
    setState(() {
      _pinBuffer.add(digit);
      _errorText = null;
    });
    if (_pinBuffer.length == _pinLength) {
      _verifyPin();
    }
  }

  void _onDelete() {
    if (_pinBuffer.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pinBuffer.removeLast();
      _errorText = null;
    });
  }

  Future<void> _verifyPin() async {
    final pin = _pinBuffer.join();
    final ok = await widget.lockService.verifyPin(pin);
    if (!mounted) return;
    if (ok) {
      HapticFeedback.heavyImpact();
      widget.onUnlock();
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _pinBuffer.clear();
        _errorText = 'Incorrect PIN';
        _shake = true;
      });
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) setState(() => _shake = false);
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

        // App icon & title
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: colorScheme.primary,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.picture_as_pdf_rounded,
            size: 32,
            color: Colors.white,
          ),
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
          'Enter your PIN to unlock',
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 36),

        // PIN dots
        _PinDots(
          length: _pinLength,
          filledCount: _pinBuffer.length,
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
        const SizedBox(height: 12),

        // Biometric button
        if (widget.biometricAvailable)
          IconButton(
            icon: Icon(
              Icons.fingerprint_rounded,
              size: 36,
              color: colorScheme.primary,
            ),
            onPressed: _onBiometric,
            tooltip: 'Unlock with biometrics',
          ),

        const Spacer(flex: 1),

        // Numeric keypad
        _NumericKeypad(
          onDigit: _onDigit,
          onDelete: _onDelete,
          canDelete: _pinBuffer.isNotEmpty,
          colorScheme: colorScheme,
        ),

        const Spacer(flex: 2),
      ],
    );
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

  const _NumericKeypad({
    required this.onDigit,
    required this.onDelete,
    required this.canDelete,
    required this.colorScheme,
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
                  onTap: () => onDigit(d),
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
              onTap: () => onDigit(0),
            ),
            _KeyButton(
              icon: Icons.backspace_outlined,
              onTap: canDelete ? onDelete : null,
              disabled: !canDelete,
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
