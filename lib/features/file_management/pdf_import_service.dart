// Copyright (c) 2026 Freya. All rights reserved.
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// The folder inside app documents where individual PDF imports land, matching
/// where [FileOperationsProvider.saveToLocal] writes local saves so the whole
/// library is scanned from one place.
const String kImportsDirName = 'FreyaPDF';

/// A single file selected for import.
///
/// The full [bytes] buffer is deliberately held in memory: SAF content URIs
/// (e.g. Google Drive) stream and can't be seeked, so per the import guards we
/// read the entire stream into memory before hashing or writing anything.
class PdfImportSource {
  final String name;
  final Uint8List bytes;

  const PdfImportSource({required this.name, required this.bytes});

  int get sizeBytes => bytes.length;
}

/// Result of importing one source.
enum PdfImportStatus {
  /// Copied into the library.
  imported,

  /// Skipped because an identical file is already in the library.
  duplicate,

  /// Failed to write to disk.
  failed,
}

class PdfImportResult {
  final PdfImportSource source;
  final PdfImportStatus status;

  /// Absolute path of the committed copy, when [status] == imported.
  final String? committedPath;

  /// Short reason, populated for failures only.
  final String? failureReason;

  const PdfImportResult({
    required this.source,
    required this.status,
    this.committedPath,
    this.failureReason,
  });

  bool get isImported => status == PdfImportStatus.imported;
  bool get isDuplicate => status == PdfImportStatus.duplicate;
}

/// Performs individual PDF imports into the app's default library.
///
/// Imports are copied (never moved) into app documents so the library entry
/// survives the original being moved or deleted. Every file is written
/// atomically (`.tmp` then rename) so a mid-batch failure or cancellation never
/// leaves a partial/corrupt PDF. Files identical to an existing library entry
/// (same first-1MB SHA-256 + size) are silently skipped — never given a
/// `file(1).pdf` name.
class PdfImportService {
  PdfImportService._();

  /// Resolve the directory imports copy into. Callers replace [root] with a
  /// temp directory in tests to keep the service unit-testable.
  static Future<Directory> docsDirFor({String? root}) async {
    if (root != null) {
      return Directory(root);
    }
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/$kImportsDirName');
  }

  /// Fingerprint: SHA-256 of the first 1MB of [bytes] combined with the total
  /// size. Two files that differ only past the first 1MB are still
  /// distinguished by size, so this is collision-resistant for our purposes
  /// while staying cheap for large files.
  static String fingerprintBytes(Uint8List bytes) {
    final headLen = bytes.length < (1024 * 1024) ? bytes.length : 1024 * 1024;
    final head = bytes.sublist(0, headLen);
    final digest = sha256.convert(head).toString();
    return '$digest:${bytes.length}';
  }

  /// Compute the fingerprint of an existing library file on disk.
  static Future<String> fingerprintFile(File file) async {
    final raf = await file.open();
    try {
      final len = await raf.length();
      final headLen = len < (1024 * 1024) ? len : 1024 * 1024;
      final head = await raf.read(headLen);
      final digest = sha256.convert(head).toString();
      return '$digest:$len';
    } finally {
      await raf.close();
    }
  }

  /// Scan a directory for existing fingerprints. Returns a set of fingerprints
  /// so the dedupe set can be built once up-front for a batch.
  static Future<Set<String>> scanDirectoryFingerprints(String dirPath) async {
    final result = <String>{};
    final dir = Directory(dirPath);
    if (!await dir.exists()) return result;
    await for (final entity in dir.list(recursive: false, followLinks: false)) {
      if (entity is File && entity.path.endsWith('.pdf')) {
        try {
          result.add(await fingerprintFile(entity));
        } catch (e) {
          debugPrint('PdfImportService: fingerprint failed ${entity.path}: $e');
        }
      }
    }
    return result;
  }

  /// Resolve a non-colliding destination path in [dir] for [fileName]. If the
  /// plain name is taken, appends ` (1)`, ` (2)`, … before the extension —
  /// mirroring the existing decrypt collision pattern. Note: the dedupe guard
  /// means this race is rare; it only protects against two sources sharing a
  /// name within a batch while being distinct files.
  static Future<String> resolveDestPath(Directory dir, String fileName) async {
    var destPath = '${dir.path}/$fileName';
    if (!await File(destPath).exists()) return destPath;
    final dotIndex = fileName.lastIndexOf('.');
    final stem = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
    final ext = dotIndex > 0 ? fileName.substring(dotIndex) : '';
    var i = 1;
    do {
      destPath = '${dir.path}/$stem ($i)$ext';
      i++;
    } while (await File(destPath).exists());
    return destPath;
  }

  /// Write [bytes] to [destPath] atomically: write to `destPath.tmp`, then
  /// rename on success. On any failure the temp file is best-effort cleaned up
  /// and the error rethrown so the caller can record a per-file failure without
  /// aborting the batch.
  static Future<void> writeFileBytesAtomic(
    String destPath,
    Uint8List bytes,
  ) async {
    final tmpFile = File('$destPath.tmp');
    try {
      if (await tmpFile.exists()) {
        await tmpFile.delete();
      }
      await tmpFile.writeAsBytes(bytes);
      await tmpFile.rename(destPath);
    } catch (_) {
      try {
        if (await tmpFile.exists()) {
          await tmpFile.delete();
        }
      } catch (_) {}
      rethrow;
    }
  }

  /// Reserve a small safety margin so a quota check doesn't pass only to have
  /// the write land on a nearly-full volume. [availableBytes] of null means the
  /// platform couldn't report a value — skip the check and rely on the atomic
  /// `.tmp`-then-rename write to fail cleanly rather than corrupt.
  ///
  /// Returns true only when [cumulativeBytes] clearly exceeds what's left after
  /// the margin; otherwise false (import can proceed).
  static bool quotaExceeds(int? availableBytes, int cumulativeBytes) {
    if (availableBytes == null) return false;
    const marginBytes = 8 * 1024 * 1024; // 8 MiB leeway
    return cumulativeBytes > (availableBytes - marginBytes);
  }

  /// Import a batch of [sources] into [dir].
  ///
  /// Pure logic (no BuildContext): builds the existing-fingerprint set once up
  /// front, then imports each source atomically. The batch never aborts on a
  /// single failure — every outcome is collected so the caller can summarise.
  /// [onProgress] is invoked after each file with 1-based (completed, total);
  /// [isCancelled] (optional) lets a caller stop early, leaving already-written
  /// copies in place.
  static Future<List<PdfImportResult>> importBatch({
    required List<PdfImportSource> sources,
    required Directory dir,
    void Function(int completed, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final existingFingerprints = await scanDirectoryFingerprints(dir.path);
    final results = <PdfImportResult>[];
    final total = sources.length;
    for (var i = 0; i < total; i++) {
      if (isCancelled?.call() ?? false) break;
      final source = sources[i];
      // Add this batch's own fingerprint as we go so two distinct-but-identical
      // sources in the same batch don't both land (dedupe within the batch).
      final result =
          await importOne(
            source: source,
            dir: dir,
            existingFingerprints: existingFingerprints,
          );
      if (result.isImported && result.committedPath != null) {
        existingFingerprints.add(fingerprintBytes(source.bytes));
      }
      results.add(result);
      onProgress?.call(i + 1, total);
    }
    return results;
  }

  /// Import a single [source] into [dir]. Returns the outcome.
  static Future<PdfImportResult> importOne({
    required PdfImportSource source,
    required Directory dir,
    required Set<String> existingFingerprints,
  }) async {
    final fingerprint = fingerprintBytes(source.bytes);
    if (existingFingerprints.contains(fingerprint)) {
      return PdfImportResult(source: source, status: PdfImportStatus.duplicate);
    }
    try {
      final destPath = await resolveDestPath(dir, source.name);
      await writeFileBytesAtomic(destPath, source.bytes);
      return PdfImportResult(
        source: source,
        status: PdfImportStatus.imported,
        committedPath: destPath,
      );
    } catch (e) {
      return PdfImportResult(
        source: source,
        status: PdfImportStatus.failed,
        failureReason: e.toString(),
      );
    }
  }
}
