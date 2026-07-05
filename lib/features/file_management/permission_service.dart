import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

class PermissionService {
  /// Check if we have storage permission.
  /// On Android 11+, requires MANAGE_EXTERNAL_STORAGE.
  /// On Android 10 and below, requires READ_EXTERNAL_STORAGE.
  static Future<bool> hasStoragePermission() async {
    if (!Platform.isAndroid) return true;

    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdkInt = androidInfo.version.sdkInt;

    if (sdkInt >= 30) {
      // Android 11+ — need MANAGE_EXTERNAL_STORAGE
      return await Permission.manageExternalStorage.isGranted;
    } else {
      // Android 10 and below
      return await Permission.storage.isGranted;
    }
  }

  /// Request storage permission. Returns true if granted.
  static Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdkInt = androidInfo.version.sdkInt;

    if (sdkInt >= 30) {
      // Android 11+ — MANAGE_EXTERNAL_STORAGE requires opening settings
      final status = await Permission.manageExternalStorage.status;
      if (status.isGranted) return true;

      // Request — this will show a dialog explaining why we need it
      final result = await Permission.manageExternalStorage.request();
      if (result.isGranted) return true;

      // If denied, we need to open settings manually
      return false;
    } else {
      // Android 10 and below — standard permission request
      final result = await Permission.storage.request();
      return result.isGranted;
    }
  }

  /// Open app settings so user can grant permission manually.
  static Future<void> openSettings() async {
    await openAppSettings();
  }

  /// Show a dialog explaining why we need storage permission.
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
        return await requestStoragePermission();
      }
    }
    return false;
  }
}
