// Copyright (c) 2026 Freya. All rights reserved.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Certificate pinning for the small set of hosts FreyaPDF talks to.
///
/// FreyaPDF is local-first; its only outbound traffic is the update check
/// against GitHub's API (`api.github.com`) and the APK download from the
/// GitHub release assets CDN (`objects.githubusercontent.com`). Both are
/// pinned here to their SHA-256 SPKI fingerprints (RFC 7469).
///
/// Pins come from `openssl s_client -showcerts -connect <host>:443` →
/// `openssl x509 -pubkey -noout -in cert.pem | openssl pkey -pubin -outform der \
///   | openssl dgst -sha256 -binary | openssl enc -base64`.
abstract final class CertPinning {
  static const _pins = <String, String>{
    // api.github.com — GitHub API, used for release metadata.
    'api.github.com': 'rlkAiJEjAwr5USvccZ2NlLzz7elZETOabSnkRvKdow0=',

    // objects.githubusercontent.com — GitHub release asset CDN (APK download).
    'objects.githubusercontent.com': 'PaZDXCM44SEEkf5qy7PN/gi0Z1u+nhGbRcKHSZQxhmA=',
  };

  CertPinning._();

  /// Whether [host] has an associated pin. Only hosts we know about are ever
  /// pinned; everything else is left to the OS trust store.
  static bool hasPinFor(String host) => _pins.containsKey(host);

  /// Verify that [certificate] matches the configured SPKI pin for [host].
  ///
  /// Returns true when the certificate is valid for the pinned host, or when
  /// the host is not pinned (so we never break non-pinned connections).
  /// Returns false when the host IS pinned but the certificate does NOT match
  /// the expected fingerprint — this is what blocks a MITM.
  static bool verify(String host, X509Certificate certificate) {
    final expectedPin = _pins[host];
    if (expectedPin == null) return true;

    try {
      final actualPin = spkiSha256Base64(certificate);
      return _constantTimeEquals(actualPin, expectedPin);
    } catch (_) {
      // If we cannot compute the pin for a pinned host, fail closed.
      return false;
    }
  }

  /// Compute the RFC 7469 pin (base64-encoded SHA-256 of the DER-encoded
  /// SubjectPublicKeyInfo) for a [certificate].
  static String spkiSha256Base64(X509Certificate certificate) {
    final spki = extractSpkiDer(certificate.der);
    final hash = sha256.convert(spki).bytes;
    return base64Encode(hash);
  }

  /// Extract the DER bytes of the SubjectPublicKeyInfo from a certificate's
  /// DER encoding (RFC 5280: `tbsCertificate.subjectPublicKeyInfo`).
  static Uint8List extractSpkiDer(List<int> der) {
    final reader = _DerReader(der);

    // Certificate ::= SEQUENCE { tbsCertificate, signatureAlgorithm, signature }
    final certContent = reader.enterSequence();

    // Descend into tbsCertificate ::= SEQUENCE { ... }.
    // Fixed order of leading fields: version [0], serialNumber (INTEGER),
    // signature (SEQUENCE), issuer (SEQUENCE), validity (SEQUENCE),
    // subject (SEQUENCE), subjectPublicKeyInfo (SEQUENCE).
    final tbs = certContent.enterSequence();

    if (tbs.peekTag() == 0xA0) {
      tbs.readContextTagged(0x00); // version [0]
    }
    tbs.skipElement(); // serialNumber
    tbs.enterSequence(); // signature
    tbs.enterSequence(); // issuer
    tbs.enterSequence(); // validity
    tbs.enterSequence(); // subject

    // subjectPublicKeyInfo ::= SEQUENCE -- capture the raw DER bytes.
    return tbs.readRawElement();
  }

  /// Constant-time comparison to avoid timing-side-channel leaks.
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }
}

/// Minimal DER reader sufficient to walk a certificate down to its
/// `subjectPublicKeyInfo`. Only the subset of DER we need is implemented.
class _DerReader {
  final Uint8List _data;
  int _offset;

  _DerReader(List<int> bytes)
      : _data = Uint8List.fromList(bytes),
        _offset = 0;

  bool get isAtEnd => _offset >= _data.length;

  int peekTag() => _data[_offset];

  /// Read a single identifier octet.
  int _readIdentifier() => _data[_offset++];

  /// Read the content length octets, returning (isConstructed, contentLength).
  (bool, int) _readLength() {
    final first = _data[_offset++];
    if (first < 0x80) return (first & 0x20 != 0, first);
    final numBytes = first & 0x7f;
    if (numBytes > 4) throw FormatException('Oversized DER length');
    var length = 0;
    for (var i = 0; i < numBytes; i++) {
      length = (length << 8) | _data[_offset++];
    }
    return (first & 0x20 != 0, length);
  }

  /// Read a SEQUENCE tag and return its content end offset, leaving the cursor
  /// at the first child element.
  int readSequence() {
    final id = _readIdentifier();
    if (id != 0x30) {
      throw FormatException('Expected SEQUENCE, got 0x${id.toRadixString(16)}');
    }
    final (_, length) = _readLength();
    final end = _offset + length;
    if (end > _data.length) throw FormatException('SEQUENCE exceeds buffer');
    return end;
  }

  /// Advance past the current element (identifier + length + content).
  void skipElement() {
    _readIdentifier();
    final (_, length) = _readLength();
    _offset += length;
    if (_offset > _data.length) throw FormatException('Element overflow');
  }

  /// Read an explicit-context constructed-tagged value (used for version [0],
  /// whose identifier is 0xA0).
  void readContextTagged(int tag) {
    final id = _readIdentifier();
    if (id != (0xA0 | tag)) {
      throw FormatException(
        'Expected context tag 0x${tag.toRadixString(16)}, got '
        '0x${id.toRadixString(16)}',
      );
    }
    final (_, length) = _readLength();
    _offset += length;
    if (_offset > _data.length) throw FormatException('Tag overflow');
  }

  /// Read a SEQUENCE's contents, fully consuming the element from this reader
  /// and returning a sub-reader positioned over just that SEQUENCE's content.
  _DerReader enterSequence() {
    final end = readSequence();
    final next = _DerReader(_data.sublist(_offset, end));
    _offset = end; // consume the entire SEQUENCE element from the parent
    return next;
  }

  /// Return the raw bytes (identifier + length + content) of the element the
  /// cursor currently points at, advancing past it.
  Uint8List readRawElement() {
    final start = _offset;
    final id = _readIdentifier();
    if ((id & 0x20) == 0) {
      throw FormatException(
        'Expected constructed value, got 0x${id.toRadixString(16)}',
      );
    }
    final (_, length) = _readLength();
    final end = _offset + length;
    if (end > _data.length) throw FormatException('Constructed overflow');
    final bytes = _data.sublist(start, end);
    _offset = end;
    return bytes;
  }
}
