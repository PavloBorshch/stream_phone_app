/// The set of languages the app can display in. Only [english] is
/// implemented today; add new cases here (language code + display name)
/// as translations are added — this enum is the extension point.
enum AppLocale {
  english('en', 'English');

  const AppLocale(this.languageCode, this.displayName);

  final String languageCode;
  final String displayName;

  static AppLocale fromLanguageCode(String? code) {
    return AppLocale.values.firstWhere(
      (locale) => locale.languageCode == code,
      orElse: () => AppLocale.english,
    );
  }
}
