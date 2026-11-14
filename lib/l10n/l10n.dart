export 'app_localizations.dart';

import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_localizations.dart';

extension L10nExtension on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}

/// ProcessLama's localizations without Material's or Cupertino's: the
/// app's strings and the widgets layer's. Meridian adds its own in
/// `MeridianApp`. Use it instead of the generated
/// `AppLocalizations.localizationsDelegates`, which still lists the
/// Material and Cupertino delegates.
const List<LocalizationsDelegate<dynamic>> processLamaLocalizationsDelegates = [
  AppLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];
