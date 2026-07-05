import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Thin wrapper around local_auth for biometric unlock.
///
/// Handles availability checks, biometric prompt with fallback
/// to device PIN/password, and error mapping.
class BiometricAuthService {
  final LocalAuthentication _localAuth;

  BiometricAuthService({LocalAuthentication? localAuth})
      : _localAuth = localAuth ?? LocalAuthentication();

  /// Whether the device supports biometric authentication
  /// (fingerprint, face, or iris).
  Future<bool> canAuthenticate() async {
    try {
      return await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// List of available biometric types on the device.
  Future<List<BiometricType>> availableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } on PlatformException {
      return [];
    } on MissingPluginException {
      return [];
    }
  }

  /// Prompt the user for biometric (or device PIN/password) authentication.
  ///
  /// Returns `true` if authentication succeeded, `false` otherwise.
  /// [reason] is shown in the system biometric dialog.
  Future<bool> authenticate({
    String reason = 'Authenticate to unlock encrypted PDF',
    bool persistAcrossBackgrounding = true,
    bool biometricOnly = false,
  }) async {
    try {
      final result = await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: biometricOnly,
        persistAcrossBackgrounding: persistAcrossBackgrounding,
        sensitiveTransaction: true,
      );
      return result;
    } on LocalAuthException catch (e) {
      // Map known failure codes to a clean false; everything else rethrows
      switch (e.code) {
        case LocalAuthExceptionCode.userCanceled:
        case LocalAuthExceptionCode.noCredentialsSet:
        case LocalAuthExceptionCode.noBiometricsEnrolled:
        case LocalAuthExceptionCode.noBiometricHardware:
        case LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable:
        case LocalAuthExceptionCode.userRequestedFallback:
        case LocalAuthExceptionCode.timeout:
        case LocalAuthExceptionCode.systemCanceled:
        case LocalAuthExceptionCode.temporaryLockout:
        case LocalAuthExceptionCode.biometricLockout:
          return false;
        case LocalAuthExceptionCode.authInProgress:
        case LocalAuthExceptionCode.uiUnavailable:
        case LocalAuthExceptionCode.deviceError:
        case LocalAuthExceptionCode.unknownError:
          return false;
      }
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Stop any ongoing authentication session.
  Future<bool> stopAuthentication() async {
    try {
      return await _localAuth.stopAuthentication();
    } catch (_) {
      return false;
    }
  }
}
