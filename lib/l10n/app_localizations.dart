import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In de, this message translates to:
  /// **'FindUX'**
  String get appTitle;

  /// No description provided for @searchHint.
  ///
  /// In de, this message translates to:
  /// **'Sicher suchen...'**
  String get searchHint;

  /// No description provided for @settingsTitle.
  ///
  /// In de, this message translates to:
  /// **'Einstellungen'**
  String get settingsTitle;

  /// No description provided for @languageLabel.
  ///
  /// In de, this message translates to:
  /// **'Sprache'**
  String get languageLabel;

  /// No description provided for @countryLabel.
  ///
  /// In de, this message translates to:
  /// **'Land'**
  String get countryLabel;

  /// No description provided for @regionLabel.
  ///
  /// In de, this message translates to:
  /// **'Bundesland/Region'**
  String get regionLabel;

  /// No description provided for @cityLabel.
  ///
  /// In de, this message translates to:
  /// **'Stadt'**
  String get cityLabel;

  /// No description provided for @zipLabel.
  ///
  /// In de, this message translates to:
  /// **'PLZ'**
  String get zipLabel;

  /// No description provided for @optionalInfo.
  ///
  /// In de, this message translates to:
  /// **'Diese Angaben sind optional. Sie helfen jedoch, lokale Suchergebnisse zu präzisieren.'**
  String get optionalInfo;

  /// No description provided for @saveButton.
  ///
  /// In de, this message translates to:
  /// **'Speichern'**
  String get saveButton;

  /// No description provided for @privacyPolicy.
  ///
  /// In de, this message translates to:
  /// **'Datenschutzerklärung'**
  String get privacyPolicy;

  /// No description provided for @termsOfService.
  ///
  /// In de, this message translates to:
  /// **'AGB'**
  String get termsOfService;

  /// No description provided for @onboardingWelcome.
  ///
  /// In de, this message translates to:
  /// **'Willkommen bei FindUX'**
  String get onboardingWelcome;

  /// No description provided for @onboardingText.
  ///
  /// In de, this message translates to:
  /// **'Ihre Privatsphäre ist unsere Priorität. Alle Daten bleiben lokal auf Ihrem Gerät.'**
  String get onboardingText;

  /// No description provided for @startSearch.
  ///
  /// In de, this message translates to:
  /// **'Suche starten'**
  String get startSearch;

  /// No description provided for @knowledgeSession.
  ///
  /// In de, this message translates to:
  /// **'Wissens-Sitzung'**
  String get knowledgeSession;

  /// No description provided for @whatSearch.
  ///
  /// In de, this message translates to:
  /// **'Was suchst du?'**
  String get whatSearch;

  /// No description provided for @whySearch.
  ///
  /// In de, this message translates to:
  /// **'Warum suchst du?'**
  String get whySearch;

  /// No description provided for @topicHint.
  ///
  /// In de, this message translates to:
  /// **'Thema...'**
  String get topicHint;

  /// No description provided for @reasonHint.
  ///
  /// In de, this message translates to:
  /// **'Grund...'**
  String get reasonHint;

  /// No description provided for @startAnalysis.
  ///
  /// In de, this message translates to:
  /// **'Analyse starten'**
  String get startAnalysis;

  /// No description provided for @learningMode.
  ///
  /// In de, this message translates to:
  /// **'Lernmodus'**
  String get learningMode;

  /// No description provided for @unlockHardware.
  ///
  /// In de, this message translates to:
  /// **'Hardware entsperren'**
  String get unlockHardware;

  /// No description provided for @authenticating.
  ///
  /// In de, this message translates to:
  /// **'Autorisierung...'**
  String get authenticating;

  /// No description provided for @zeroDataPolicy.
  ///
  /// In de, this message translates to:
  /// **'Zero-Data Policy aktiv.'**
  String get zeroDataPolicy;

  /// No description provided for @secureAccess.
  ///
  /// In de, this message translates to:
  /// **'Hardware-verschlüsselter Zugriff.'**
  String get secureAccess;

  /// No description provided for @next.
  ///
  /// In de, this message translates to:
  /// **'Weiter'**
  String get next;

  /// No description provided for @back.
  ///
  /// In de, this message translates to:
  /// **'Zurück'**
  String get back;

  /// No description provided for @start.
  ///
  /// In de, this message translates to:
  /// **'Starten'**
  String get start;

  /// No description provided for @reviewFeedback.
  ///
  /// In de, this message translates to:
  /// **'Feedback prüfen'**
  String get reviewFeedback;

  /// No description provided for @noFeedback.
  ///
  /// In de, this message translates to:
  /// **'Kein Feedback zum Export vorhanden.'**
  String get noFeedback;

  /// No description provided for @sendFeedbackSafe.
  ///
  /// In de, this message translates to:
  /// **'Sicher übertragen'**
  String get sendFeedbackSafe;

  /// No description provided for @deleteFeedback.
  ///
  /// In de, this message translates to:
  /// **'Löschen'**
  String get deleteFeedback;

  /// No description provided for @feedbackTitle.
  ///
  /// In de, this message translates to:
  /// **'Feedback Export'**
  String get feedbackTitle;

  /// No description provided for @feedbackDesc.
  ///
  /// In de, this message translates to:
  /// **'Nur diese Daten werden übertragen:'**
  String get feedbackDesc;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
