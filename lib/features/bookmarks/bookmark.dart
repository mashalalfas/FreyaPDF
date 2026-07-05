import 'dart:math';

/// A single bookmark within a PDF document.
///
/// Stored per-document and used for quick navigation
/// to a saved page location.
class Bookmark {
  Bookmark({
    String? id,
    required this.filePath,
    required this.pageNumber,
    this.label,
    DateTime? createdAt,
  })  : id = id ?? _generateId(),
        createdAt = createdAt ?? DateTime.now();

  /// Generate a unique ID without external dependencies.
  static String _generateId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final rand = Random().nextInt(0xFFFFFF);
    return 'bm_${now}_$rand';
  }

  final String id;
  final String filePath;
  final int pageNumber;
  final String? label;
  final DateTime createdAt;

  /// JSON serialization
  Map<String, dynamic> toJson() => {
        'id': id,
        'filePath': filePath,
        'pageNumber': pageNumber,
        if (label != null) 'label': label,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
        id: json['id'] as String,
        filePath: json['filePath'] as String,
        pageNumber: json['pageNumber'] as int,
        label: json['label'] as String?,
        createdAt: json['createdAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int)
            : DateTime.now(),
      );

  Bookmark copyWith({
    String? id,
    String? filePath,
    int? pageNumber,
    String? label,
    DateTime? createdAt,
  }) =>
      Bookmark(
        id: id ?? this.id,
        filePath: filePath ?? this.filePath,
        pageNumber: pageNumber ?? this.pageNumber,
        label: label ?? this.label,
        createdAt: createdAt ?? this.createdAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Bookmark &&
          id == other.id &&
          filePath == other.filePath &&
          pageNumber == other.pageNumber &&
          label == other.label;

  @override
  int get hashCode => Object.hash(id, filePath, pageNumber, label);
}
