import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'update_service.dart';

/// States for the update flow.
enum UpdateState {
  idle,
  checking,
  updateAvailable,
  downloading,
  downloaded,
  upToDate,
  noInternet,
  error,
}

/// ChangeNotifier that manages the update lifecycle.
class UpdateProvider extends ChangeNotifier {
  final UpdateService _service;

  UpdateProvider({UpdateService? service})
      : _service = service ?? UpdateService();

  UpdateState _state = UpdateState.idle;
  GitHubRelease? _release;
  double? _downloadProgress; // 0..1
  String? _downloadedApkPath;
  String? _errorMessage;
  String _currentVersion = '';

  UpdateState get state => _state;
  GitHubRelease? get release => _release;
  double? get downloadProgress => _downloadProgress;
  String? get downloadedApkPath => _downloadedApkPath;
  String? get errorMessage => _errorMessage;
  String get currentVersion => _currentVersion;

  CancelToken? _cancelToken;

  /// Initialize by reading the current app version.
  Future<void> init() async {
    final info = await PackageInfo.fromPlatform();
    _currentVersion = info.version;
    notifyListeners();
  }

  /// Check GitHub for a newer release.
  Future<void> checkForUpdate({bool silent = false}) async {
    _state = UpdateState.checking;
    _errorMessage = null;
    if (!silent) notifyListeners();

    final result = await _service.checkForUpdate();

    switch (result.status) {
      case UpdateStatus.updateAvailable:
        _state = UpdateState.updateAvailable;
        _release = result.release;
        break;
      case UpdateStatus.upToDate:
        _state = UpdateState.upToDate;
        break;
      case UpdateStatus.noInternet:
        _state = UpdateState.noInternet;
        _errorMessage = 'No internet connection';
        break;
      case UpdateStatus.rateLimited:
        _state = UpdateState.error;
        _errorMessage = 'Unable to check for updates';
        break;
      case UpdateStatus.error:
        _state = UpdateState.error;
        _errorMessage = result.errorMessage ?? 'Something went wrong';
        break;
    }
    notifyListeners();
  }

  /// Download the APK from the latest release.
  Future<void> downloadUpdate() async {
    if (_release == null) return;

    final apkAsset = _release!.assets.firstWhere(
      (a) => a.name.toLowerCase().endsWith('.apk'),
      orElse: () => const GitHubAsset(
        name: '',
        downloadUrl: '',
        size: 0,
      ),
    );

    if (apkAsset.downloadUrl.isEmpty) {
      _state = UpdateState.error;
      _errorMessage = 'No APK found in release';
      notifyListeners();
      return;
    }

    _state = UpdateState.downloading;
    _downloadProgress = 0;
    _cancelToken = CancelToken();
    notifyListeners();

    final path = await _service.downloadApk(
      apkAsset,
      onProgress: (p) {
        _downloadProgress = p;
        notifyListeners();
      },
      cancelToken: _cancelToken,
    );

    if (path != null) {
      _state = UpdateState.downloaded;
      _downloadedApkPath = path;
      _downloadProgress = 1.0;
    } else if (_cancelToken?.isCancelled == true) {
      _state = UpdateState.updateAvailable;
      _downloadProgress = null;
    } else {
      _state = UpdateState.error;
      _errorMessage = 'Download failed';
      _downloadProgress = null;
    }
    notifyListeners();
  }

  /// Install the previously downloaded APK.
  Future<void> installUpdate() async {
    if (_downloadedApkPath == null) return;
    await _service.installApk(_downloadedApkPath!);
  }

  /// Cancel an in-progress download.
  void cancelDownload() {
    _cancelToken?.cancel();
  }

  /// Reset back to idle (e.g. after dismissing a dialog).
  void reset() {
    _state = UpdateState.idle;
    _release = null;
    _downloadProgress = null;
    _downloadedApkPath = null;
    _errorMessage = null;
    notifyListeners();
  }
}
