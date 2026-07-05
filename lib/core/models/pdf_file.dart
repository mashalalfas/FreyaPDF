import 'dart:io';

class PdfFile {
  final String path;
  final String name;
  final int sizeBytes;
  final DateTime modified;

  /// Tag IDs associated with this file. Populated at render time by
  /// [TagProvider] — the source of truth lives in SharedPreferences, not
  /// the file system or the file model itself.
  final List<String> tagIds;

  PdfFile({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.modified,
    this.tagIds = const [],
  });

  String get sizeFormatted {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get modifiedFormatted {
    final diff = DateTime.now().difference(modified);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${modified.day}/${modified.month}/${modified.year}';
  }

  File get file => File(path);

  /// Whether this file has the .pdf.enc extension (encrypted).
  bool get isEncrypted => path.endsWith('.pdf.enc');

  /// The original filename without .enc suffix, for display.
  /// "report.pdf.enc" → "report.pdf"
  String get displayName {
    if (isEncrypted) {
      return name.substring(0, name.length - 4); // strip .enc
    }
    return name;
  }

  static PdfFile fromFileSystem(FileSystemEntity entity) {
    final file = File(entity.path);
    final stat = file.statSync();
    return PdfFile(
      path: entity.path,
      name: entity.path.split(Platform.pathSeparator).last,
      sizeBytes: stat.size,
      modified: stat.modified,
    );
  }

  PdfFile copyWith({
    String? path,
    String? name,
    int? sizeBytes,
    DateTime? modified,
    List<String>? tagIds,
  }) {
    return PdfFile(
      path: path ?? this.path,
      name: name ?? this.name,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      modified: modified ?? this.modified,
      tagIds: tagIds ?? this.tagIds,
    );
  }
}
