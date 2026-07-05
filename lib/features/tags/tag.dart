import 'dart:convert';
import 'package:flutter/material.dart';

/// A user-defined tag for organizing PDFs (e.g. "Work", "Personal", "Read Later").
///
/// Tags are stored in SharedPreferences separately from the underlying PDF
/// files, so they persist across encryption/decryption and even if the
/// original file is deleted (the mapping is by absolute file path).
class Tag {
  final String id;
  final String name;
  final int color; // ARGB color value

  const Tag({
    required this.id,
    required this.name,
    required this.color,
  });

  Color get displayColor => Color(color);

  // --- Predefined palette ---
  static const List<int> palette = [
    0xFFE57373, // Red
    0xFF81C784, // Green
    0xFF64B5F6, // Blue
    0xFFFFD54F, // Yellow
    0xFFFF8A65, // Orange
    0xFFBA68C8, // Purple
    0xFF4DB6AC, // Teal
    0xFF90A4AE, // Gray
  ];

  /// Default color for new tags (Teal — matches Feya brand).
  static int get defaultColor => palette[6];

  /// Returns a contrasting foreground color (black87 or white) for the given
  /// ARGB background, using a relative-luminance heuristic.
  static Color contrastFor(int argb) {
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    // Relative luminance approximation (BT.601 weights)
    final luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0;
    return luminance > 0.6 ? Colors.black87 : Colors.white;
  }

  // --- Copy with ---
  Tag copyWith({String? name, int? color}) {
    return Tag(
      id: id,
      name: name ?? this.name,
      color: color ?? this.color,
    );
  }

  // --- JSON ---
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': color,
      };

  factory Tag.fromJson(Map<String, dynamic> json) {
    return Tag(
      id: json['id'] as String,
      name: (json['name'] as String?)?.trim() ?? '',
      color: (json['color'] as int?) ?? defaultColor,
    );
  }

  String encode() => jsonEncode(toJson());

  factory Tag.decode(String s) {
    try {
      final decoded = jsonDecode(s);
      if (decoded is Map<String, dynamic>) {
        return Tag.fromJson(decoded);
      }
    } catch (_) {}
    return Tag(id: '', name: '', color: defaultColor);
  }

  // --- Equality ---
  @override
  bool operator ==(Object other) => other is Tag && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Tag($id, $name, 0x${color.toRadixString(16)})';
}
