import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

class PermissionService {
  /// Check if we have storage permission.
  /// On Android 10+, uses MediaStore — no special permission needed.
  /// On Android 9 and below, uses READ_EXTERNAL_STORAGE.
  static Future<bool> hasStoragePermission() async {
    if (!Platform.isAndroid) return true;

    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdkInt = androidInfo.version.sdkInt;

    if (sdkInt >= 29) {
      // Android 10+ — verify we can actually access the filesystem
      return await hasDirectoryAccess();
    } else {
      // Android 9 and below
      return await Permission.storage.isGranted;
    }
  }

  /// On Android 10+, test if we can actually access the filesystem.
  /// Without MANAGE_EXTERNAL_STORAGE, direct Directory() access fails.
  static Future<bool> hasDirectoryAccess() async {
    if (!Platform.isAndroid) return true;

    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdkInt = androidInfo.version.sdkInt;

    if (sdkInt >= 30) {
      // Android 11+ — try reading a known path
      try {
        final dir = Directory('/storage/emulated/0/Download');
        if (await dir.exists()) {
          await dir.list().first;
          return true;
        }
      } catch (_) {
        return false;
      }
      return false;
    }
    // Android 10 uses scoped storage but some paths are still accessible
    if (sdkInt == 29) return true;

    // Below Android 10
    return await Permission.storage.isGranted;
  }

  /// Request storage permission. Returns true if granted.
  static Future<bool> requestStoragePermission(BuildContext ctx) async {
    if (!Platform.isAndroid) return true;

    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdkInt = androidInfo.version.sdkInt;

    if (sdkInt >= 30) {
      // Android 11+ — MANAGE_EXTERNAL_STORAGE removed; use SAF file picker
      if (ctx.mounted) {
        await showDialog(
          context: ctx,
          builder: (dctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: Theme.of(ctx).colorScheme.primary),
                const SizedBox(width: 10),
                const Text('Storage Access'),
              ],
            ),
            content: const Text(
              'Feya PDF uses Android\'s built-in file picker to open PDFs on this device.\n\n'
              'Just tap "Open PDF" and select your files.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dctx),
                child: const Text('Got it'),
              ),
            ],
          ),
        );
      }
      return true;
    } else {
      // Android 9 and below — standard permission request
      final result = await Permission.storage.request();
      return result.isGranted;
    }
  }

  /// Open app settings so user can grant permission manually.
  static Future<void> openSettings() async {
    await openAppSettings();
  }

  /// Show a dialog explaining how to access files.
  static Future<bool> showPermissionDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.folder_rounded, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            const Text('Storage Access'),
          ],
        ),
        content: const Text(
          'Feya PDF needs access to storage to scan and read your PDF files.\n\n'
          'Please grant "All files access" permission in the next screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Grant Access'),
          ),
        ],
      ),
    );

    if (result == true) {
      if (context.mounted) {
        return await requestStoragePermission(context);
      }
    }
    return false;
  }
}
