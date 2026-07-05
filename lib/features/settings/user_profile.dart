class UserProfile {
  final String name;
  final String email;
  final String? avatarPath; // local file path or null (placeholder)

  const UserProfile({
    this.name = '',
    this.email = '',
    this.avatarPath,
  });

  UserProfile copyWith({
    String? name,
    String? email,
    String? avatarPath,
    bool clearAvatar = false,
  }) {
    return UserProfile(
      name: name ?? this.name,
      email: email ?? this.email,
      avatarPath: clearAvatar ? null : (avatarPath ?? this.avatarPath),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
        'avatarPath': avatarPath,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      avatarPath: json['avatarPath'] as String?,
    );
  }
}
