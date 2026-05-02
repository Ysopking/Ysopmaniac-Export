import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

class SettingsState {
  final String plz;
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

  const SettingsState({
    required this.plz,
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
  });

  SettingsState copyWith({
    String? plz,
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
  }) {
    return SettingsState(
      plz: plz ?? this.plz,
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
    );
  }
}

const SettingsState _defaultSettings = SettingsState(
  plz: '',
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
);

class SettingsNotifier extends StateNotifier<SettingsState> {
  final SecurityService _security;

  SettingsNotifier(this._security) : super(_defaultSettings);

  // Alle SharedPreferences-Keys, die zum App-Settings-Modell gehoeren.
  static const _allPrefsKeys = <String>[
    'plz',
    'beruf',
    'jahr',
    'searchengine',
    'language',
    'country',
    'allowFeedback',
    'enableYouthProtection',
    'sources',
    'files',
    'mode',
  ];

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    // Einmal-Migration: alte Klartext-PII aus SharedPreferences in den Vault
    // verschieben und danach aus Prefs entfernen.
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
        debugPrint('PII migration to encrypted vault completed.');
      }
    } catch (e) {
      debugPrint('PII migration skipped: $e');
    }

    String pPlz = '';
    String pBeruf = '';
    int pJahr = 1990;
    try {
      final box = _security.vaultBox;
      pPlz = (box.get('plz') as String?) ?? '';
      pBeruf = (box.get('beruf') as String?) ?? '';
      pJahr = (box.get('jahr') as int?) ?? 1990;
    } catch (_) {
      // Vault nicht verfuegbar -> Defaults verwenden, KEIN Klartext-Fallback.
    }

    state = SettingsState(
      plz: pPlz,
      beruf: pBeruf,
      jahr: pJahr,
      searchEngine: prefs.getString('searchengine') ?? 'google',
      language: prefs.getString('language') ?? 'de',
      country: prefs.getString('country') ?? 'de',
      allowFeedback: prefs.getBool('allowFeedback') ?? false,
      enableYouthProtection: prefs.getBool('enableYouthProtection') ?? true,
      sources: prefs.getStringList('sources') ?? const ['alle'],
      files: prefs.getStringList('files') ?? const ['alle'],
      mode: prefs.getString('mode') ?? 'standard',
    );
  }

  Future<void> updateSettings(SettingsState newState) async {
    state = newState;

    // PII -> Vault (verschluesselt)
    try {
      final box = _security.vaultBox;
      await box.put('plz', newState.plz);
      await box.put('beruf', newState.beruf);
      await box.put('jahr', newState.jahr);
    } catch (e) {
      debugPrint('Vault write failed: $e');
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
  }

  Future<void> updateField({
    String? plz,
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
  }) {
    final newState = state.copyWith(
      plz: plz,
      beruf: beruf,
      searchEngine: searchEngine,
      language: language,
      country: country,
      allowFeedback: allowFeedback,
      enableYouthProtection: enableYouthProtection,
      jahr: jahr,
      sources: sources,
      files: files,
      mode: mode,
    );
    return updateSettings(newState);
  }

  // Komplettes Loeschen ALLER persistenten Settings (Privacy-"Notbremse").
  // - Vault wird komplett geleert (PII)
  // - alle Settings-Keys aus SharedPreferences entfernt
  // - State wird auf Defaults zurueckgesetzt
  Future<void> wipeAll() async {
    try {
      final box = _security.vaultBox;
      await box.clear();
    } catch (e) {
      debugPrint('Vault clear failed: $e');
    }
    final prefs = await SharedPreferences.getInstance();
    for (final key in _allPrefsKeys) {
      await prefs.remove(key);
    }
    // Such-Historie / Lern-Gewichte ebenfalls entfernen
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
