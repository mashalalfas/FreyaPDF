class SecureFolder {
  final String name;
  final String path;
  final bool isLocked;
  final int fileCount;
  final DateTime createdAt;

  const SecureFolder({
    required this.name,
    required this.path,
    this.isLocked = true,
    this.fileCount = 0,
    required this.createdAt,
  });

  SecureFolder copyWith({
    String? name,
    String? path,
    bool? isLocked,
    int? fileCount,
    DateTime? createdAt,
  }) {
    return SecureFolder(
      name: name ?? this.name,
      path: path ?? this.path,
      isLocked: isLocked ?? this.isLocked,
      fileCount: fileCount ?? this.fileCount,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
