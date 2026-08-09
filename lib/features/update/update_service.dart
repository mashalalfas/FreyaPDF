// Copyright (c) 2026 Freya. All rights reserved.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:freya_pdf/build_config.dart';
import 'package:freya_pdf/core/security/secure_http_client.dart';

/// Describes a single GitHub release asset (e.g. the APK).
class GitHubAsset {
  final String name;
  final String downloadUrl;
  final int size;

  const GitHubAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
  });

  factory GitHubAsset.fromJson(Map<String, dynamic> json) {
    return GitHubAsset(
      name: json['name'] as String? ?? '',
      downloadUrl: json['browser_download_url'] as String? ?? '',
      size: json['size'] as int? ?? 0,
    );
  }
}

/// Represents a parsed GitHub release.
class GitHubRelease {
  final String tagName;
  final String body;
  final List<GitHubAsset> assets;

  const GitHubRelease({
    required this.tagName,
    required this.body,
    required this.assets,
  });

  factory GitHubRelease.fromJson(Map<String, dynamic> json) {
    final rawAssets = json['assets'] as List<dynamic>? ?? [];
    return GitHubRelease(
      tagName: json['tag_name'] as String? ?? '',
      body: json['body'] as String? ?? '',
      assets: rawAssets
          .map((a) => GitHubAsset.fromJson(a as Map<String, dynamic>))
          .toList(),
    );
  }

  /// The version string with leading "v" stripped.
  String get version => tagName.replaceFirst(RegExp(r'^v'), '');
}

/// Result of an update check.
enum UpdateStatus {
  upToDate,
  updateAvailable,
  noInternet,
  rateLimited,
  error,
}

class UpdateCheckResult {
  final UpdateStatus status;
  final GitHubRelease? release;
  final String? errorMessage;

  const UpdateCheckResult({
    required this.status,
    this.release,
    this.errorMessage,
  });
}

/// Progress callback: value ∈ [0.0, 1.0], or null when unknown.
typedef DownloadProgress = void Function(double? progress);

class UpdateService {
  static const _owner = 'mashalalfas';
  static const _repo = 'FreyaPDF';
  static const _releasesUrl =
      'https://api.github.com/repos/$_owner/$_repo/releases/latest';

  final http.Client _client;

  UpdateService({http.Client? client})
      : _client = client ?? SecureHttpClient.create();

  // ── Play Store gating ─────────────────────────────────────────────

  /// Returns false when running a Play Store build (auto-update disabled).
  bool get _canUpdate => !BuildConfig.isPlayStoreBuild;

  // ── Version comparison ──────────────────────────────────────────────

  /// Compare two semver strings like "1.2.3". Returns true when [remote]
  /// is strictly newer than [current].
  static bool isUpdateAvailable(String current, String remote) {
    final c = _parseVersion(current);
    final r = _parseVersion(remote);
    for (var i = 0; i < 3; i++) {
      if (r[i] > c[i]) return true;
      if (r[i] < c[i]) return false;
    }
    return false;
  }

  static List<int> _parseVersion(String v) {
    final parts = v.split('.').map(int.tryParse).toList();
    return [
      parts.isNotEmpty ? (parts[0] ?? 0) : 0,
      parts.length > 1 ? (parts[1] ?? 0) : 0,
      parts.length > 2 ? (parts[2] ?? 0) : 0,
    ];
  }

  // ── Network ─────────────────────────────────────────────────────────

  /// Fetch the latest release from GitHub.
  Future<GitHubRelease?> fetchLatestRelease() async {
    if (!_canUpdate) return null;
    final response = await _client.get(
      Uri.parse(_releasesUrl),
      headers: {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    );

    if (response.statusCode == 200) {
      return GitHubRelease.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    return null;
  }

  /// Full check: fetch release, compare with installed version.
  Future<UpdateCheckResult> checkForUpdate() async {
    if (!_canUpdate) {
      return const UpdateCheckResult(status: UpdateStatus.upToDate);
    }
    try {
      final info = await PackageInfo.fromPlatform();
      final release = await fetchLatestRelease();

      if (release == null) {
        return const UpdateCheckResult(status: UpdateStatus.rateLimited);
      }

      if (isUpdateAvailable(info.version, release.version)) {
        return UpdateCheckResult(
          status: UpdateStatus.updateAvailable,
          release: release,
        );
      }

      return UpdateCheckResult(status: UpdateStatus.upToDate);
    } on SocketException {
      return const UpdateCheckResult(status: UpdateStatus.noInternet);
    } on TimeoutException {
      return const UpdateCheckResult(status: UpdateStatus.noInternet);
    } on http.ClientException {
      return const UpdateCheckResult(status: UpdateStatus.noInternet);
    } catch (e) {
      return const UpdateCheckResult(status: UpdateStatus.error);
    }
  }

  // ── Download ────────────────────────────────────────────────────────

  /// Download the APK asset to the app's cache directory.
  /// Returns the local file path, or null on failure.
  Future<String?> downloadApk(
    GitHubAsset asset, {
    DownloadProgress? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (!_canUpdate) return null;
    try {
      final cacheDir = await getTemporaryDirectory();
      final filePath = '${cacheDir.path}/${asset.name}';

      // Delete stale file if it exists.
      final existing = File(filePath);
      if (await existing.exists()) {
        await existing.delete();
      }

      final request = http.Request('GET', Uri.parse(asset.downloadUrl));
      final response = await _client.send(request);

      if (response.statusCode != 200) {
        return null;
      }

      final totalBytes = response.contentLength;
      var receivedBytes = 0;
      final fileSink = File(filePath).openWrite();

      await response.stream.forEach((chunk) {
        if (cancelToken?.isCancelled == true) {
          fileSink.close();
          return;
        }
        receivedBytes += chunk.length;
        fileSink.add(chunk);
        if (onProgress != null && totalBytes != null && totalBytes > 0) {
          onProgress(receivedBytes / totalBytes);
        }
      });

      await fileSink.flush();
      await fileSink.close();

      if (cancelToken?.isCancelled == true) {
        // Clean up partial download.
        final partial = File(filePath);
        if (await partial.exists()) await partial.delete();
        return null;
      }

      return filePath;
    } catch (e) {
      return null;
    }
  }

  /// Open a downloaded APK file for installation.
  Future<void> installApk(String filePath) async {
    await OpenFilex.open(filePath);
  }

  /// Delete stale APK files from the cache directory.
  Future<void> cleanupStaleApks() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final files = cacheDir.listSync();
      for (final f in files) {
        if (f is File && f.path.toLowerCase().endsWith('.apk')) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}

/// Simple cancellation token.
class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}
