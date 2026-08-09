// Copyright (c) 2026 Freya. All rights reserved.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freya_pdf/core/security/cert_pinning.dart';

void main() {
  group('CertPinning', () {
    test('known hosts have real pins registered', () {
      expect(CertPinning.hasPinFor('api.github.com'), isTrue);
      expect(CertPinning.hasPinFor('objects.githubusercontent.com'), isTrue);
      expect(CertPinning.hasPinFor('unrelated.example.com'), isFalse);
    });

    test('unpinned hosts pass through (delegated to OS trust store)', () {
      // cert is irrelevant here; no pin means accept.
      expect(CertPinning.verify('unrelated.example.com', _dummyCert()), isTrue);
    });

    test('SPKI extraction matches the RFC 7469 pin computed by openssl', () {
      final der = _generateCertDer();
      final extracted = CertPinning.extractSpkiDer(der);

      // Independent reference: digest of the same SPKI via openssl.
      final dir = Directory.systemTemp.createTempSync('freya_pin_ref');
      try {
        final pem = _writeDerAsCert(dir, der);
        final expectedPin = _opensslSpkiPin(pem);
        final actualPin = base64Encode(sha256.convert(extracted).bytes);
        expect(actualPin, expectedPin);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('verify rejects a cert that does not match a pinned host', () {
      // The pinned host api.github.com has a registered pin that (in practice)
      // will never match a freshly generated local self-signed cert, so the
      // MITM defence must fail closed.
      final cert = _dummyCert();
      expect(CertPinning.verify('api.github.com', cert), isFalse);
    });
  });
}

/// Generate a fresh self-signed RSA-2048 cert, return its DER bytes.
List<int> _generateCertDer() {
  final dir = Directory.systemTemp.createTempSync('freya_pin_gen');
  try {
    final key = '${dir.path}/key.pem';
    final pem = '${dir.path}/cert.pem';
    final res = Process.runSync('openssl', [
      'req', '-x509', '-newkey', 'rsa:2048',
      '-keyout', key, '-out', pem,
      '-days', '1', '-nodes',
      '-subj', '/CN=localhost',
    ]);
    if (res.exitCode != 0) {
      throw StateError('openssl failed: ${res.stderr}');
    }
    return _pemToDer(File(pem).readAsStringSync());
  } finally {
    dir.deleteSync(recursive: true);
  }
}

List<int> _pemToDer(String pem) {
  final body = pem
      .replaceAll('-----BEGIN CERTIFICATE-----', '')
      .replaceAll('-----END CERTIFICATE-----', '')
      .replaceAll(RegExp(r'\s'), '');
  return base64Decode(body);
}

/// Reuse the DER bytes to write a fresh PEM cert file for openssl reference.
String _writeDerAsCert(Directory dir, List<int> der) {
  final b64 = base64Encode(der);
  final lines = <String>[];
  lines.add('-----BEGIN CERTIFICATE-----');
  for (var i = 0; i < b64.length; i += 64) {
    lines.add(b64.substring(i, i + 64 > b64.length ? b64.length : i + 64));
  }
  lines.add('-----END CERTIFICATE-----');
  final path = '${dir.path}/cert.pem';
  File(path).writeAsStringSync(lines.join('\n'));
  return path;
}

String _opensslSpkiPin(String pemPath) {
  final res = Process.runSync('sh', [
    '-c',
    "openssl x509 -in '$pemPath' -pubkey -noout | "
        'openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | '
        'openssl enc -base64',
  ]);
  if (res.exitCode != 0) {
    throw StateError('openssl pin failed: ${res.stderr}');
  }
  return (res.stdout as String).trim();
}

// A minimal viable X509Certificate stub is not available from dart:io (no
// public constructor). `verify` only calls into CertPinning.spkiSha256Base64,
// which reads `certificate.der`; we provide a lightweight fake.
X509Certificate _dummyCert() {
  final der = _generateCertDer();
  // Wrap DER so spkiSha256Base64 can read `certificate.der`. X509Certificate
  // is abstract; a noSuchMethod-based stub is simpler than a hand-rolled DER
  // for the "reject" path which never depends on real values.
  return _FakeCert(Uint8List.fromList(_assertDer(der)));
}

List<int> _assertDer(List<int> der) {
  expect(der, isNotEmpty);
  expect(der[0], 0x30, reason: 'certificate should begin with a SEQUENCE');
  return der;
}

class _FakeCert implements X509Certificate {
  _FakeCert(this.der);
  @override
  final Uint8List der;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
