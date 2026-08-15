// Copyright (c) 2026 Freya. All rights reserved.
import 'package:flutter/material.dart';

/// Shared, consistently-styled snackbar helper.
///
/// Floating, rounded (12), warm surface (tracking the M3 warm ramp) with a
/// teal accent action. Covers the common content-only case and an optional
/// inline action.
class FreyaSnackBar {
  FreyaSnackBar._();

  /// Show a styled snackbar using [context].
  static void show(
    BuildContext context,
    String message, {
    String? action,
    VoidCallback? onAction,
    SnackBarBehavior behavior = SnackBarBehavior.floating,
    Duration? duration,
  }) {
    _showVia(
      message,
      scheme: Theme.of(context).colorScheme,
      messenger: ScaffoldMessenger.of(context),
      action: action,
      onAction: onAction,
      behavior: behavior,
      duration: duration,
    );
  }

  /// Show a styled snackbar from a pre-captured [messenger] and [scheme].
  ///
  /// For call sites reached across an async gap where holding onto
  /// [BuildContext] would trip `use_build_context_synchronously`.
  static void showVia(
    ScaffoldMessengerState messenger,
    ColorScheme scheme,
    String message, {
    String? action,
    VoidCallback? onAction,
    SnackBarBehavior behavior = SnackBarBehavior.floating,
    Duration? duration,
  }) {
    _showVia(
      message,
      scheme: scheme,
      messenger: messenger,
      action: action,
      onAction: onAction,
      behavior: behavior,
      duration: duration,
    );
  }

  static void _showVia(
    String message, {
    required ColorScheme scheme,
    required ScaffoldMessengerState messenger,
    String? action,
    VoidCallback? onAction,
    SnackBarBehavior behavior = SnackBarBehavior.floating,
    Duration? duration,
  }) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: behavior,
        duration: duration ?? const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        action: (action != null && onAction != null)
            ? SnackBarAction(
                label: action,
                onPressed: onAction,
                textColor: scheme.primary,
              )
            : null,
      ),
    );
  }
}
