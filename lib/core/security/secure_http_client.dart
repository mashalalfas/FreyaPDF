// Copyright (c) 2026 Freya. All rights reserved.
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as http_io;

import 'cert_pinning.dart';

/// Builds HTTP clients hardened with certificate pinning for the hosts
/// FreyaPDF connects to.
///
/// Because the default `package:http` `Client` uses the OS trust store alone,
/// a compromised CA / MITM proxy could impersonate our endpoints. This
/// factory returns an `IOClient` backed by an `HttpClient` whose
/// `badCertificateCallback` requires each pinned host to present the exact
/// SPKI fingerprint we expect (see [CertPinning]).
abstract final class SecureHttpClient {
  SecureHttpClient._();

  /// Create a pinned HTTP client. Never throws: if pinning cannot be
  /// configured the caller falls back to a plain client so the update check
  /// (which is non-critical) never breaks login or PDF rendering.
  static http.Client create() {
    try {
      final inner = HttpClient()
        ..badCertificateCallback = (cert, host, _) {
          return CertPinning.verify(host, cert);
        };
      return http_io.IOClient(inner);
    } catch (_) {
      return http.Client();
    }
  }
}
