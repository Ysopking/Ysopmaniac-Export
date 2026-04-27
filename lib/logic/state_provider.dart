import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/security_service.dart';
import '../services/learning_service.dart';

// Providers for Services
final securityServiceProvider = Provider((ref) => SecurityService());
final learningServiceProvider = Provider((ref) => LearningService());

// Auth State
final authProvider = StateProvider<bool>((ref) => false);

// Onboarding State
final onboardingDoneProvider = StateProvider<bool>((ref) => false);

// Settings State
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

  SettingsState({
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
      enableYouthProtection: enableYouthProtection ?? this.enableYouthProtection,
      jahr: jahr ?? this.jahr,
      sources: sources ?? this.sources,
      files: files ?? this.files,
      mode: mode ?? this.mode,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier() : super(SettingsState(
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
  ));

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    state = SettingsState(
      plz: prefs.getString('plz') ?? '',
      beruf: prefs.getString('beruf') ?? '',
      searchEngine: prefs.getString('searchengine') ?? 'google',
      language: prefs.getString('language') ?? 'de',
      country: prefs.getString('country') ?? 'de',
      allowFeedback: prefs.getBool('allowFeedback') ?? false,
      enableYouthProtection: prefs.getBool('enableYouthProtection') ?? true,
      jahr: prefs.getInt('jahr') ?? 1990,
      sources: prefs.getStringList('sources') ?? ['alle'],
      files: prefs.getStringList('files') ?? ['alle'],
      mode: prefs.getString('mode') ?? 'standard',
    );
  }

  Future<void> updateSettings(SettingsState newState) async {
    state = newState;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('plz', state.plz);
    await prefs.setString('beruf', state.beruf);
    await prefs.setString('searchengine', state.searchEngine);
    await prefs.setString('language', state.language);
    await prefs.setString('country', state.country);
    await prefs.setBool('allowFeedback', state.allowFeedback);
    await prefs.setBool('enableYouthProtection', state.enableYouthProtection);
    await prefs.setInt('jahr', state.jahr);
    await prefs.setStringList('sources', state.sources);
    await prefs.setStringList('files', state.files);
    await prefs.setString('mode', state.mode);
  }

  void updateField({
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
    updateSettings(newState);
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>((ref) => SettingsNotifier());
