import 'dart:math';

/// A single text highlight within a PDF document.
///
/// Stored per-document and rendered as a semi-transparent overlay
/// on the matching text.
class HighlightData {
  HighlightData({
    String? id,
    required this.filePath,
    required this.pageNumber,
    required this.text,
    this.color = _defaultColor,
    DateTime? createdAt,
  })  : id = id ?? _generateId(),
        createdAt = createdAt ?? DateTime.now();

  static const int _defaultColor = 0xFFFFEB3B; // Material Yellow

  /// Generate a unique ID without external dependencies.
  static String _generateId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final rand = Random().nextInt(0xFFFFFF);
    return 'hl_${now}_$rand';
  }

  final String id;
  final String filePath;
  final int pageNumber;
  final String text;
  final int color; // ARGB int
  final DateTime createdAt;

  /// JSON serialization
  Map<String, dynamic> toJson() => {
        'id': id,
        'filePath': filePath,
        'pageNumber': pageNumber,
        'text': text,
        'color': color,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory HighlightData.fromJson(Map<String, dynamic> json) => HighlightData(
        id: json['id'] as String,
        filePath: json['filePath'] as String,
        pageNumber: json['pageNumber'] as int,
        text: json['text'] as String,
        color: json['color'] as int? ?? _defaultColor,
        createdAt: json['createdAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int)
            : DateTime.now(),
      );

  HighlightData copyWith({
    String? id,
    String? filePath,
    int? pageNumber,
    String? text,
    int? color,
    DateTime? createdAt,
  }) =>
      HighlightData(
        id: id ?? this.id,
        filePath: filePath ?? this.filePath,
        pageNumber: pageNumber ?? this.pageNumber,
        text: text ?? this.text,
        color: color ?? this.color,
        createdAt: createdAt ?? this.createdAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HighlightData &&
          id == other.id &&
          filePath == other.filePath &&
          pageNumber == other.pageNumber &&
          text == other.text &&
          color == other.color;

  @override
  int get hashCode => Object.hash(id, filePath, pageNumber, text, color);
}
