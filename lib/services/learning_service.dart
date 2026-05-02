import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/findux_stopwords.dart';

/// Lern- und Gewichtungs-Modul (v2).
///
/// Was getrackt wird (alles verschluesselt, lokal):
///   - Suchanfragen: query+url+filter+mode+sources+files+stammdaten-snapshot
///   - Feedback: thumbs up/down + optionaler Kommentar (idempotent pro search)
///
/// Wie gewichtet wird (lokale Gewichte in SharedPreferences):
///   - weight_kw_<wort>      Keyword-Gewicht
///   - weight_filter_<f>     Quellen-/Datei-Filter
///   - weight_mode_<m>       precise/standard/discover/recent
///   - weight_domain_<host>  bevorzugte/abgewertete Domains
///   - weight_employment_<t> Beschaeftigungstyp-Korrelation (Stammdaten)
///
/// Anti-Drift Massnahmen:
///   - Asymmetrische, ABER GEDAEMPFTE Bumps (up=+0.20, down=-0.25)
///   - Hard-Limits pro Gewichts-Typ (Keywords [0.4..2.5], Domains [0.1..5.0])
///   - 5% Decay Richtung 1.0 nach jedem Analyse-Lauf
///   - Idempotent: pro Suche maximal EIN Feedback gewertet
///   - Search-Log rotiert auf max. 200 Eintraege
class LearningService {
  static const String _boxName = 'learning_data';
  static const String _logBoxName = 'learning_log';
  static const String _feedbackBoxName = 'learning_feedback';

  static const double _decayFactor = 0.05;
  static const int _maxSearchLogEntries = 200;

  // Additive Bumps statt multiplikativ -> linear, kein Runaway.
  static const double _bumpUp = 0.20;
  static const double _bumpDown = 0.25;

  // Hard-Limits pro Gewichts-Typ
  static const double _kwMin = 0.4;
  static const double _kwMax = 2.5;
  static const double _filterMin = 0.2;
  static const double _filterMax = 4.0;
  static const double _modeMin = 0.3;
  static const double _modeMax = 3.0;
  static const double _domainMin = 0.1;
  static const double _domainMax = 5.0;

  bool _initialized = false;

  Future<void> init(List<int> cipherKey) async {
    if (_initialized) return;
    final cipher = HiveAesCipher(cipherKey);
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox<dynamic>(_boxName, encryptionCipher: cipher);
    }
    if (!Hive.isBoxOpen(_logBoxName)) {
      await Hive.openBox<dynamic>(_logBoxName, encryptionCipher: cipher);
    }
    if (!Hive.isBoxOpen(_feedbackBoxName)) {
      await Hive.openBox<dynamic>(_feedbackBoxName, encryptionCipher: cipher);
    }
    _initialized = true;
  }

  Future<void> trackSearch({
    required String query,
    required String url,
    required Map<String, dynamic> settings,
    required List<String> sources,
    required List<String> files,
    required String mode,
  }) async {
    if (!Hive.isBoxOpen(_boxName)) return;
    final box = Hive.box<dynamic>(_boxName);
    final key = DateTime.now().millisecondsSinceEpoch.toString();
    await box.put(key, <String, dynamic>{
      'query': query,
      'url': url,
      'engine': (settings['searchengine'] as String?) ?? 'google',
      'employmentType':
          (settings['employmentType'] as String?) ?? 'student',
      'language': (settings['language'] as String?) ?? 'de',
      'timestamp': DateTime.now().toIso8601String(),
      'sources': sources,
      'files': files,
      'mode': mode,
    });
    await _rotateLog(box);
  }

  /// Idempotent: pro search_id wird nur das ERSTE Feedback ausgewertet.
  /// Spaetere Bewertungen ueberschreiben den Kommentar, aber zaehlen NICHT
  /// noch einmal als Gewichts-Bump.
  Future<void> trackFeedback(String rating, {String? comment}) async {
    if (!Hive.isBoxOpen(_feedbackBoxName) ||
        !Hive.isBoxOpen(_boxName)) return;
    final box = Hive.box<dynamic>(_feedbackBoxName);
    final searchBox = Hive.box<dynamic>(_boxName);

    if (searchBox.isEmpty) return;
    final lastSearchId = searchBox.keys.last.toString();

    // Schon Feedback fuer diese Suche da? -> nur Kommentar updaten
    final existing = box.values.cast<dynamic>().firstWhere(
          (e) {
            if (e is! Map) return false;
            return e['search_id']?.toString() == lastSearchId;
          },
          orElse: () => null,
        );
    if (existing != null) {
      final m = Map<String, dynamic>.from(existing as Map);
      m['comment'] = comment ?? m['comment'] ?? '';
      // Key der existierenden Entry finden + aktualisieren
      for (final k in box.keys) {
        final v = box.get(k);
        if (v is Map && v['search_id']?.toString() == lastSearchId) {
          await box.put(k, m);
          break;
        }
      }
      return;
    }

    final key = DateTime.now().millisecondsSinceEpoch.toString();
    await box.put(key, <String, dynamic>{
      'search_id': lastSearchId,
      'rating': rating,
      'comment': comment ?? '',
      'timestamp': DateTime.now().toIso8601String(),
      'applied': false,
    });
  }

  Future<void> checkAndAnalyze() async {
    final prefs = await SharedPreferences.getInstance();
    final lastAnalysis = prefs.getInt('last_analysis') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - lastAnalysis > 7 * 24 * 60 * 60 * 1000) {
      await _analyzeAndOptimize(prefs);
      await _applyDecay(prefs);
      await prefs.setInt('last_analysis', now);
    }
  }

  Future<void> _analyzeAndOptimize(SharedPreferences prefs) async {
    if (!Hive.isBoxOpen(_boxName) ||
        !Hive.isBoxOpen(_feedbackBoxName)) return;
    final searchBox = Hive.box<dynamic>(_boxName);
    final feedbackBox = Hive.box<dynamic>(_feedbackBoxName);

    final searchData = Map<dynamic, dynamic>.from(searchBox.toMap());

    // Nur noch nicht-applied Feedbacks verarbeiten
    final pendingKeys = <dynamic>[];
    for (final k in feedbackBox.keys) {
      final v = feedbackBox.get(k);
      if (v is Map && v['applied'] != true) pendingKeys.add(k);
    }

    int processed = 0;
    for (final fk in pendingKeys) {
      final fValue = Map<String, dynamic>.from(feedbackBox.get(fk) as Map);
      final searchId = fValue['search_id'];
      final rating = fValue['rating'] as String?;
      if (searchId == null || rating == null) continue;
      if (!searchData.containsKey(searchId)) continue;

      final search = Map<String, dynamic>.from(searchData[searchId] as Map);
      final isPositive = rating == 'up';
      final delta = isPositive ? _bumpUp : -_bumpDown;
      final kwDelta = delta * 0.5; // gedaempft fuer Keywords

      // Mode
      final mode = (search['mode'] as String?) ?? 'standard';
      await _bumpAdditive(prefs, 'weight_mode_$mode', delta, _modeMin, _modeMax);

      // Filter (Quellen + Dateitypen)
      final sources =
          (search['sources'] as List<dynamic>?) ?? const <dynamic>[];
      final files =
          (search['files'] as List<dynamic>?) ?? const <dynamic>[];
      for (final filter in [...sources, ...files]) {
        if (filter == 'alle') continue; // 'alle' nicht lernen
        await _bumpAdditive(prefs, 'weight_filter_$filter', delta,
            _filterMin, _filterMax);
      }

      // Beschaeftigungstyp-Korrelation (Stammdaten-Lernen)
      final empType =
          (search['employmentType'] as String?) ?? 'student';
      await _bumpAdditive(prefs, 'weight_employment_$empType', delta * 0.3,
          _modeMin, _modeMax);

      // Keyword-Gewichte
      final query = (search['query'] as String?) ?? '';
      final language = (search['language'] as String?) ?? 'de';
      await _extractAndWeightKeywords(query, kwDelta, prefs, language);

      // Domain-Gewicht
      final url = (search['url'] as String?) ?? '';
      final host = _extractHost(url);
      if (host != null) {
        await _bumpAdditive(prefs, 'weight_domain_$host', delta,
            _domainMin, _domainMax);
      }

      // Markiere als verarbeitet
      fValue['applied'] = true;
      await feedbackBox.put(fk, fValue);
      processed++;
    }

    await _logPrivacyAction(
        'Interessen-Modell verfeinert ($processed Feedbacks).');

    if (kDebugMode) {
      debugPrint('Analyzer: applied $processed feedback events');
    }
  }

  /// Decay: alle Gewichte 5% Richtung 1.0 schieben.
  Future<void> _applyDecay(SharedPreferences prefs) async {
    final keys =
        prefs.getKeys().where((k) => k.startsWith('weight_')).toList();
    int updated = 0;
    for (final k in keys) {
      final v = prefs.getDouble(k);
      if (v == null) continue;
      final next = v + (1.0 - v) * _decayFactor;
      if ((next - 1.0).abs() < 0.02) {
        await prefs.remove(k);
      } else {
        await prefs.setDouble(k, next);
      }
      updated++;
    }
    if (kDebugMode) {
      debugPrint('Weight decay applied to $updated keys.');
    }
  }

  /// Additive Aenderung — KEIN Multiplizieren.
  Future<void> _bumpAdditive(SharedPreferences prefs, String key,
      double delta, double min, double max) async {
    final current = prefs.getDouble(key) ?? 1.0;
    final next = (current + delta).clamp(min, max);
    await prefs.setDouble(key, next);
  }

  Future<void> _logPrivacyAction(String message) async {
    if (!Hive.isBoxOpen(_logBoxName)) return;
    final logBox = Hive.box<dynamic>(_logBoxName);
    await logBox.add(<String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'action': 'interest_model_refinement',
      'message': message,
    });
    // Log auch rotieren
    while (logBox.length > 50) {
      await logBox.deleteAt(0);
    }
  }

  /// Begrenzung des Such-Logs auf _maxSearchLogEntries Eintraege.
  Future<void> _rotateLog(Box<dynamic> box) async {
    while (box.length > _maxSearchLogEntries) {
      final oldestKey = box.keys.first;
      await box.delete(oldestKey);
    }
  }

  List<Map<String, dynamic>> getFeedbackForReview() {
    if (!Hive.isBoxOpen(_feedbackBoxName)) {
      return const <Map<String, dynamic>>[];
    }
    final box = Hive.box<dynamic>(_feedbackBoxName);
    return box.values
        .map((dynamic e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> clearAllFeedback() async {
    if (!Hive.isBoxOpen(_feedbackBoxName)) return;
    await Hive.box<dynamic>(_feedbackBoxName).clear();
  }

  Future<void> _extractAndWeightKeywords(String query, double delta,
      SharedPreferences prefs, String language) async {
    // Operatoren raus
    final clean = query
        .replaceAll(
            RegExp(
                r'\b(site|inurl|intitle|intext|filetype|ext|before|after|allintitle|allintext|allinurl):\S+'),
            ' ')
        .replaceAll(RegExp(r'-\S+'), ' ')
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .toLowerCase();

    final stopwords = stopwordsForLanguage(language);
    final words = clean
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 3 && !stopwords.contains(w))
        .toSet() // Dedup pro Query
        .toList();

    for (final word in words) {
      await _bumpAdditive(
          prefs, 'weight_kw_$word', delta, _kwMin, _kwMax);
    }
    if (kDebugMode) {
      debugPrint('Updated keyword weights: ${words.length} terms');
    }
  }

  String? _extractHost(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.replaceFirst(RegExp(r'^www\.'), '');
      const searchEngines = {
        'google.com', 'google.de', 'bing.com', 'duckduckgo.com',
        'startpage.com', 'search.brave.com',
      };
      if (searchEngines.contains(host)) return null;
      return host.isEmpty ? null : host;
    } catch (_) {
      return null;
    }
  }
}
