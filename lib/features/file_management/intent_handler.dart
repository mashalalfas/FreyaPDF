import 'dart:async';
import 'package:flutter/services.dart';

/// Handles Android "Open with" intents — receives PDF URIs from other apps.
class IntentHandler {
  static const _channel = MethodChannel('com.feya.feya_pdf/intent');
  static final _controller = StreamController<String>.broadcast();

  /// Stream of file paths received from "Open with" intents.
  static Stream<String> get onFileOpened => _controller.stream;

  static void init() {
    // Listen for intents while app is running
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openFile') {
        final path = call.arguments as String?;
        if (path != null && path.isNotEmpty) {
          _controller.add(path);
        }
      }
    });
  }

  /// Get the initial file path if app was launched via "Open with".
  static Future<String?> getInitialFilePath() async {
    try {
      final path = await _channel.invokeMethod<String>('getInitialFilePath');
      if (path != null && path.isNotEmpty) return path;
    } catch (_) {}
    return null;
  }

  /// Copy a content:// URI to a temp file and return the local path.
  /// Android content URIs can't be read directly as File paths.
  static Future<String?> copyContentUri(String uriString) async {
    try {
      final path = await _channel.invokeMethod<String>('copyContentUri', uriString);
      if (path != null && path.isNotEmpty) return path;
    } catch (_) {}
    return null;
  }
}
