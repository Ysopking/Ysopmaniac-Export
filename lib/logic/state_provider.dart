import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/chrome_import_service.dart';
import '../services/security_service.dart';
import '../services/learning_service.dart';

// Diese Provider werden in main.dart per overrideWithValue mit den
// initialisierten Service-Instanzen ueberschrieben.
final securityServiceProvider = Provider<SecurityService>((ref) {
  throw UnimplementedError(
      'securityServiceProvider muss in main() per ProviderScope override gesetzt werden.');
});

final learningServiceProvider = Provider<LearningService>((ref) {
  throw UnimplementedError(
      'learningServiceProvider muss in main() per ProviderScope override gesetzt werden.');
});

final initFailedProvider = StateProvider<bool>((ref) => false);

final authProvider = StateProvider<bool>((ref) => false);
final authErrorProvider = StateProvider<String?>((ref) => null);
final onboardingDoneProvider = StateProvider<bool>((ref) => false);
final firstLaunchProvider = StateProvider<bool>((ref) => true);

/// Beschaeftigungstyp.
/// - student: Schueler/Student/Auszubildender
/// - rentner: Rente/Pension
/// - vollzeit: Vollzeit-Job (loest "beruf"-Feld als Jobrichtung aus)
/// - teilzeit: Teilzeit-Job (loest "beruf"-Feld als Jobrichtung aus)
/// - erwerbslos: ohne Beschaeftigung / Job-Suche
const employmentTypes = <String>[
  'student',
  'rentner',
  'vollzeit',
  'teilzeit',
  'erwerbslos',
];

class SettingsState {
  final String plz;
  final String employmentType;
  /// Familienstatus: 'single' | 'familie' | 'alleinerziehend'.
  /// Leichte Vorgewichtung — wird durch Interessen + Chronik verfeinert.
  final String familyStatus;
  /// Optionale Jobrichtung. Nur sinnvoll wenn employmentType in {vollzeit,teilzeit}.
  final String beruf;
  final String searchEngine;
  final String language;
  final String country;
  final bool allowFeedback;
  final bool enableYouthProtection;
  final int jahr;
  final List<String> sources;
  final List<String> files;
  final String mode;
  /// true = Suchergebnisse in Custom Tabs / SFSafariViewController (in-app)
  /// false = im externen Browser oeffnen
  final bool openInApp;
  /// Doppel-Druck der Lauter-Taste startet die Suche (nur Home-Page).
  final bool enableVolumeShortcut;
  /// Stage G: hierarchische Interessen-Auswahl als Pfade
  /// im Format `top/sub/item` (z.B. `musik/rap/sido`).
  final List<String> interests;
  /// Stage 14: Screenshot- + Recents-Sperre (Android FLAG_SECURE).
  /// Default true (privacy-by-default). Wird nativ in MainActivity.kt
  /// beim onCreate aus SharedPreferences gelesen — der Toggle hier
  /// schreibt zurueck UND ruft per MethodChannel SecureFlag.setSecure()
  /// fuer die Laufzeit auf.
  final bool disableScreenshots;

  const SettingsState({
    required this.plz,
    required this.employmentType,
    required this.familyStatus,
    required this.beruf,
    required this.searchEngine,
    required this.language,
    required this.country,
    required this.allowFeedback,
    required this.enableYouthProtection,
    required this.jahr,
    required this.sources,
    required this.files,
    required this.mode,
    required this.openInApp,
    required this.enableVolumeShortcut,
    required this.interests,
    required this.disableScreenshots,
  });

  /// Stage 14: Wahre, EFFEKTIVE Jugendschutz-Einstellung.
  /// Wenn der User noch minderjaehrig ist (Alter < 18 anhand des
  /// Geburtsjahrs), wird Jugendschutz hart erzwungen — egal was der
  /// Toggle sagt.
  bool get isMinor => (DateTime.now().year - jahr) < 18;
  bool get effectiveYouthProtection => enableYouthProtection || isMinor;

  SettingsState copyWith({
    String? plz,
    String? employmentType,
    String? familyStatus,
    String? beruf,
    String? searchEngine,
    String? language,
    String? country,
    bool? allowFeedback,
    bool? enableYouthProtection,
    int? jahr,
    List<String>? sources,
    List<String>? files,
    String? mode,
    bool? openInApp,
    bool? enableVolumeShortcut,
    List<String>? interests,
    bool? disableScreenshots,
  }) {
    return SettingsState(
      plz: plz ?? this.plz,
      employmentType: employmentType ?? this.employmentType,
      familyStatus: familyStatus ?? this.familyStatus,
      beruf: beruf ?? this.beruf,
      searchEngine: searchEngine ?? this.searchEngine,
      language: language ?? this.language,
      country: country ?? this.country,
      allowFeedback: allowFeedback ?? this.allowFeedback,
      enableYouthProtection:
          enableYouthProtection ?? this.enableYouthProtection,
      jahr: jahr ?? this.jahr,
      sources: sources ?? this.sources,
      files: files ?? this.files,
      mode: mode ?? this.mode,
      openInApp: openInApp ?? this.openInApp,
      enableVolumeShortcut:
          enableVolumeShortcut ?? this.enableVolumeShortcut,
      interests: interests ?? this.interests,
      disableScreenshots: disableScreenshots ?? this.disableScreenshots,
    );
  }
}

const SettingsState _defaultSettings = SettingsState(
  plz: '',
  employmentType: 'student',
  familyStatus: 'single',
  beruf: '',
  searchEngine: 'google',
  language: 'de',
  country: 'de',
  allowFeedback: false,
  enableYouthProtection: true,
  jahr: 1990,
  sources: ['alle'],
  files: ['alle'],
  mode: 'standard',
  openInApp: true,
  enableVolumeShortcut: false,
  interests: <String>[],
  disableScreenshots: true,
);

class SettingsNotifier extends StateNotifier<SettingsState> {
  final SecurityService _security;

  SettingsNotifier(this._security) : super(_defaultSettings);

  // Alle SharedPreferences-Keys, die zum App-Settings-Modell gehoeren.
  static const _allPrefsKeys = <String>[
    'plz',
    'beruf',
    'employmentType',
    'familyStatus',
    'jahr',
    'searchengine',
    'language',
    'country',
    'allowFeedback',
    'enableYouthProtection',
    'sources',
    'files',
    'mode',
    'openInApp',
    'enableVolumeShortcut',
    'interests',
    'disableScreenshots',
  ];

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    // Einmal-Migration: alte Klartext-PII aus SharedPreferences in den Vault.
    try {
      final box = _security.vaultBox;
      final needsMigration = !box.containsKey('plz') &&
          (prefs.containsKey('plz') ||
              prefs.containsKey('beruf') ||
              prefs.containsKey('jahr'));
      if (needsMigration) {
        await box.put('plz', prefs.getString('plz') ?? '');
        await box.put('beruf', prefs.getString('beruf') ?? '');
        await box.put('jahr', prefs.getInt('jahr') ?? 1990);
        await prefs.remove('plz');
        await prefs.remove('beruf');
        await prefs.remove('jahr');
        if (kDebugMode) debugPrint('PII migration to encrypted vault completed.');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('PII migration skipped: $e');
    }

    String pPlz = '';
    String pBeruf = '';
    String pEmploymentType = 'student';
    String pFamilyStatus = 'single';
    int pJahr = 1990;
    List<String> pInterests = const [];
    try {
      final box = _security.vaultBox;
      pPlz = (box.get('plz') as String?) ?? '';
      pBeruf = (box.get('beruf') as String?) ?? '';
      pEmploymentType =
          (box.get('employmentType') as String?) ?? 'student';
      pFamilyStatus =
          (box.get('familyStatus') as String?) ?? 'single';
      pJahr = (box.get('jahr') as int?) ?? 1990;
      // Interessen liegen ebenfalls verschluesselt im Vault.
      final raw = box.get('interests');
      if (raw is List) {
        pInterests = raw.whereType<String>().toList(growable: false);
      }
    } catch (_) {
      // Vault nicht verfuegbar -> Defaults verwenden, KEIN Klartext-Fallback.
    }

    state = SettingsState(
      plz: pPlz,
      beruf: pBeruf,
      employmentType: pEmploymentType,
      familyStatus: pFamilyStatus,
      jahr: pJahr,
      searchEngine: prefs.getString('searchengine') ?? 'google',
      language: prefs.getString('language') ?? 'de',
      country: prefs.getString('country') ?? 'de',
      allowFeedback: prefs.getBool('allowFeedback') ?? false,
      enableYouthProtection: prefs.getBool('enableYouthProtection') ?? true,
      sources: prefs.getStringList('sources') ?? const ['alle'],
      files: prefs.getStringList('files') ?? const ['alle'],
      mode: prefs.getString('mode') ?? 'standard',
      openInApp: prefs.getBool('openInApp') ?? true,
      enableVolumeShortcut:
          prefs.getBool('enableVolumeShortcut') ?? false,
      interests: pInterests,
      // Stage 14: Default ON (privacy-by-default). Der gleiche Default
      // ist auch in MainActivity.kt verankert, sodass der allererste
      // Frame schon geschuetzt ist.
      disableScreenshots: prefs.getBool('disableScreenshots') ?? true,
    );
  }

  Future<void> updateSettings(SettingsState newState) async {
    final prevInterests = state.interests;
    state = newState;

    // PII -> Vault (verschluesselt)
    try {
      final box = _security.vaultBox;
      await box.put('plz', newState.plz);
      await box.put('beruf', newState.beruf);
      await box.put('employmentType', newState.employmentType);
      await box.put('familyStatus', newState.familyStatus);
      await box.put('jahr', newState.jahr);
      await box.put('interests', newState.interests);
    } catch (e) {
      if (kDebugMode) debugPrint('Vault write failed: $e');
    }

    // Nicht-PII -> SharedPreferences (Klartext, da unkritisch)
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('searchengine', newState.searchEngine);
    await prefs.setString('language', newState.language);
    await prefs.setString('country', newState.country);
    await prefs.setBool('allowFeedback', newState.allowFeedback);
    await prefs.setBool('enableYouthProtection', newState.enableYouthProtection);
    await prefs.setStringList('sources', newState.sources);
    await prefs.setStringList('files', newState.files);
    await prefs.setString('mode', newState.mode);
    await prefs.setBool('openInApp', newState.openInApp);
    await prefs.setBool(
        'enableVolumeShortcut', newState.enableVolumeShortcut);
    await prefs.setBool('disableScreenshots', newState.disableScreenshots);

    // Stage G: nur die NEU hinzugekommenen Interessen lernen, sonst
    // wuerden wir bei jeder Settings-Aenderung doppelt bumpen.
    final added = newState.interests
        .where((i) => !prevInterests.contains(i))
        .toList(growable: false);
    if (added.isNotEmpty) {
      try {
        // 1) Token-Level: weight_kw_* fuer jeden Interesse-Pfad-Token
        await ChromeImportService.applyInterestBumps(added);
        // 2) Kategorie-Level: weight_filter_* + weight_mode_* pro Top-Kategorie
        //    (z.B. wissenschaft→academic+precise, tech→docs+precise, reisen→discover)
        //    Ergaenzt den Token-Boost um semantische Filter/Modus-Vorgewichtung.
        await LearningService.applyInterestCategoryWeights(added);
        // 3) Item-Level: hochspezifische weight_kw_* + weight_domain_* pro Item-Pfad
        //    (finanzen/soziales/buergergeld → weight_kw_buergergeld = 1.35, etc.)
        await LearningService.seedInterestItemWeights(added);
      } catch (e) {
        if (kDebugMode) debugPrint('Interest bumps failed: $e');
      }
    }
  }

  Future<void> updateField({
    String? plz,
    String? employmentType,
    String? familyStatus,
    String? beruf,
    String? searchEngine,
    String? language,
    String? country,
    bool? allowFeedback,
    bool? enableYouthProtection,
    int? jahr,
    List<String>? sources,
    List<String>? files,
    String? mode,
    bool? openInApp,
    bool? enableVolumeShortcut,
    List<String>? interests,
    bool? disableScreenshots,
  }) {
    // Stage 14: Wenn das (neue oder bestehende) Geburtsjahr Alter < 18
    // ergibt, wird Jugendschutz hart erzwungen — der Toggle kann ihn
    // dann nicht mehr ausschalten. Das ist die Backend-Seite des
    // gesperrten Toggles in der Settings-UI.
    final effJahr = jahr ?? state.jahr;
    final wouldBeMinor = (DateTime.now().year - effJahr) < 18;
    final yp = wouldBeMinor
        ? true
        : (enableYouthProtection ?? state.enableYouthProtection);
    final newState = state.copyWith(
      plz: plz,
      employmentType: employmentType,
      // Bug-Fix: familyStatus wurde zwar als Parameter empfangen,
      // aber nie an copyWith weitergegeben — Familienstatus-Aenderungen
      // gingen dadurch lautlos verloren.
      familyStatus: familyStatus,
      beruf: beruf,
      searchEngine: searchEngine,
      language: language,
      country: country,
      allowFeedback: allowFeedback,
      enableYouthProtection: yp,
      jahr: jahr,
      sources: sources,
      files: files,
      mode: mode,
      openInApp: openInApp,
      enableVolumeShortcut: enableVolumeShortcut,
      interests: interests,
      disableScreenshots: disableScreenshots,
    );
    return updateSettings(newState);
  }

  /// Komplettes Loeschen ALLER persistenten Settings (Privacy-"Notbremse").
  Future<void> wipeAll() async {
    try {
      final box = _security.vaultBox;
      await box.clear();
    } catch (e) {
      if (kDebugMode) debugPrint('Vault clear failed: $e');
    }
    final prefs = await SharedPreferences.getInstance();
    for (final key in _allPrefsKeys) {
      await prefs.remove(key);
    }
    final allKeys = prefs.getKeys().toList();
    for (final key in allKeys) {
      if (key.startsWith('weight_') ||
          key == 'searchHistory' ||
          key == 'last_analysis') {
        await prefs.remove(key);
      }
    }
    state = _defaultSettings;
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>(
  (ref) => SettingsNotifier(ref.read(securityServiceProvider)),
);
