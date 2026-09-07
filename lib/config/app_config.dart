class AppConfig {
  const AppConfig._();

  static const String defaultAppName = 'TMSX Hub';
  static const String defaultAppTagline = 'Mobile ERP';
  static const String mobileSiteRegistryBaseUrl =
      'https://developer.willshine.id';

  static const String frappeBaseUrl = String.fromEnvironment(
    'FRAPPE_BASE_URL',
    defaultValue: '',
  );

  static String get normalizedFrappeBaseUrl {
    final value = frappeBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (value.isEmpty) {
      throw StateError(
        'FRAPPE_BASE_URL belum dikonfigurasi. '
        'Jalankan Flutter dengan --dart-define-from-file=env.json.',
      );
    }
    return value;
  }

  static String get optionalFrappeBaseUrl =>
      frappeBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
}
