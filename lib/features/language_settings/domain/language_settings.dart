import 'app_locale.dart';

class LanguageSettings {
  const LanguageSettings({required this.locale});

  final AppLocale locale;

  static const defaults = LanguageSettings(locale: AppLocale.english);

  factory LanguageSettings.fromJson(Map<String, dynamic> json) {
    return LanguageSettings(locale: AppLocale.fromLanguageCode(json['languageCode'] as String?));
  }

  Map<String, dynamic> toJson() => {'languageCode': locale.languageCode};

  LanguageSettings copyWith({AppLocale? locale}) {
    return LanguageSettings(locale: locale ?? this.locale);
  }
}
