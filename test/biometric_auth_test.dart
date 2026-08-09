// Size: small — isolated unit tests for BiometricAuthService
// Uses a mock LocalAuthPlatform to test biometric-available and
// biometric-unavailable branches.

import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:freya_pdf/features/security/biometric_auth_service.dart';

/// Mock implementation of [LocalAuthPlatform] for testing authentication
/// branches without a real biometric sensor.
class MockLocalAuthPlatform extends LocalAuthPlatform
    with MockPlatformInterfaceMixin {
  bool _biometricsSupported = true;
  bool _deviceSupported = true;
  bool _authenticateResult = true;
  List<BiometricType> _enrolledBiometrics = [];
  int authenticateCallCount = 0;

  set biometricsSupported(bool value) => _biometricsSupported = value;
  set deviceSupported(bool value) => _deviceSupported = value;
  set authenticateResult(bool value) => _authenticateResult = value;
  set enrolledBiometrics(List<BiometricType> value) =>
      _enrolledBiometrics = value;

  @override
  Future<bool> deviceSupportsBiometrics() async => _biometricsSupported;

  @override
  Future<bool> isDeviceSupported() async => _deviceSupported;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    required Iterable<AuthMessages> authMessages,
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async {
    authenticateCallCount++;
    return _authenticateResult;
  }

  @override
  Future<List<BiometricType>> getEnrolledBiometrics() async =>
      _enrolledBiometrics;

  @override
  Future<bool> stopAuthentication() async => true;
}

void main() {
  late MockLocalAuthPlatform mockPlatform;
  late BiometricAuthService service;

  setUp(() {
    mockPlatform = MockLocalAuthPlatform();
    LocalAuthPlatform.instance = mockPlatform;
    service = BiometricAuthService(
      localAuth: LocalAuthentication(),
    );
  });

  group('BiometricAuthService.canAuthenticate', () {
    test('returns true when biometrics and device are supported', () async {
      mockPlatform.biometricsSupported = true;
      mockPlatform.deviceSupported = true;

      final result = await service.canAuthenticate();

      expect(result, isTrue);
    });

    test('returns false when biometrics are not available', () async {
      mockPlatform.biometricsSupported = false;
      mockPlatform.deviceSupported = false;

      final result = await service.canAuthenticate();

      expect(result, isFalse);
    });

    test('returns true when deviceSupportsBiometrics is true alone', () async {
      mockPlatform.biometricsSupported = true;
      mockPlatform.deviceSupported = false;

      final result = await service.canAuthenticate();

      expect(result, isTrue);
    });
  });

  group('BiometricAuthService.authenticate', () {
    test('returns true when authentication succeeds', () async {
      mockPlatform.authenticateResult = true;

      final result = await service.authenticate();

      expect(result, isTrue);
      expect(mockPlatform.authenticateCallCount, equals(1));
    });

    test('returns false when authentication fails', () async {
      mockPlatform.authenticateResult = false;

      final result = await service.authenticate();

      expect(result, isFalse);
      expect(mockPlatform.authenticateCallCount, equals(1));
    });
  });

  group('BiometricAuthService.availableBiometrics', () {
    test('returns list of available biometric types', () async {
      mockPlatform.enrolledBiometrics = [
        BiometricType.face,
        BiometricType.fingerprint,
      ];

      final result = await service.availableBiometrics();

      expect(result, contains(BiometricType.face));
      expect(result, contains(BiometricType.fingerprint));
    });

    test('returns empty list when no biometrics enrolled', () async {
      mockPlatform.enrolledBiometrics = [];

      final result = await service.availableBiometrics();

      expect(result, isEmpty);
    });
  });

  group('BiometricAuthService.stopAuthentication', () {
    test('returns true on successful stop', () async {
      final result = await service.stopAuthentication();
      expect(result, isTrue);
    });
  });
}
