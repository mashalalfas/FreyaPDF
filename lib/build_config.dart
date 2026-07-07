class BuildConfig {
  static const bool isPlayStoreBuild = bool.fromEnvironment(
    'PLAY_STORE_BUILD',
    defaultValue: false,
  );
}
