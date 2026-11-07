import 'package:flutter/widgets.dart';

import 'generated/app_localizations.dart';

export 'generated/app_localizations.dart';

extension L10nContext on BuildContext {
  /// Translated strings for the current language.
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// For code that has no BuildContext (SSH session messages, formatters).
/// Kept in sync with the app's language by UesshApp.
AppLocalizations currentL10n = lookupAppLocalizations(const Locale('zh'));

/// Chinese for Chinese system locales, English for everything else.
Locale resolveAppLocale(Locale? system) =>
    system?.languageCode == 'zh' ? const Locale('zh') : const Locale('en');
