import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lern- und Gewichtungs-Modul.
///
/// Was getrackt wird:
///   - Suchanfragen (Query-Text + URL + Filter + Mode)  [verschluesselt]
///   - Feedback (thumbs up/down + optionaler Kommentar) [verschluesselt]
///
/// Wie gewichtet wird (lokale Gewichte in SharedPreferences):
///   - weight_kw_<wort>      : Keyword-Gewicht (positive=Boost, negative=Demote)
///   - weight_filter_<f>     : Filter-Gewicht (Quellen + Dateitypen)
///   - weight_mode_<m>       : Mode-Gewicht (precise/standard/discover/recent)
///   - weight_domain_<host>  : Domain-Gewicht (welche Domain bringt Erfolg)
///   - weight_engine_<e>     : Such-Engine-Gewicht (google/bing/ddg/...)
///
/// Anti-Drift: jeden Lauf wird ein leichter Decay angewendet, damit alte
/// Gewichte langsam Richtung 1.0 zurueckwandern (vermeidet Lock-in auf
/// veraltete Praeferenzen).
class LearningService {
  static const String _boxName = 'learning_data';
  static const String _logBoxName = 'learning_log';
  static const String _feedbackBoxName = 'learning_feedback';

  // Decay-Faktor pro Analyse-Lauf: 5% Annaeherung an 1.0 fuer alle Gewichte.
  static const double _decayFactor = 0.05;

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
      'timestamp': DateTime.now().toIso8601String(),
      'sources': sources,
      'files': files,
      'mode': mode,
    });
  }

  Future<void> trackFeedback(String rating, {String? comment}) async {
    if (!Hive.isBoxOpen(_feedbackBoxName) || !Hive.isBoxOpen(_boxName)) return;
    final box = Hive.box<dynamic>(_feedbackBoxName);
    final searchBox = Hive.box<dynamic>(_boxName);

    String? lastSearchId;
    if (searchBox.isNotEmpty) {
      lastSearchId = searchBox.keys.last.toString();
    }

    final key = DateTime.now().millisecondsSinceEpoch.toString();
    await box.put(key, <String, dynamic>{
      'search_id': lastSearchId,
      'rating': rating,
      'comment': comment ?? '',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<void> checkAndAnalyze() async {
    final prefs = await SharedPreferences.getInstance();
    final lastAnalysis = prefs.getInt('last_analysis') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - lastAnalysis > 7 * 24 * 60 * 60 * 1000) {
      await _analyzeAndOptimize();
      await _applyDecay(prefs);
      await prefs.setInt('last_analysis', now);
    }
  }

  Future<void> _analyzeAndOptimize() async {
    if (!Hive.isBoxOpen(_boxName) || !Hive.isBoxOpen(_feedbackBoxName)) return;
    final searchBox = Hive.box<dynamic>(_boxName);
    final feedbackBox = Hive.box<dynamic>(_feedbackBoxName);

    final searchData = Map<dynamic, dynamic>.from(searchBox.toMap());
    final feedbackData = Map<dynamic, dynamic>.from(feedbackBox.toMap());
    final prefs = await SharedPreferences.getInstance();

    for (final entry in feedbackData.entries) {
      final fValue = Map<String, dynamic>.from(entry.value as Map);
      final searchId = fValue['search_id'];
      final rating = fValue['rating'];
      final multiplier = (rating == 'up') ? 1.12 : 0.82;

      if (searchId == null || !searchData.containsKey(searchId)) continue;
      final search = Map<String, dynamic>.from(searchData[searchId] as Map);

      // Mode-Gewicht
      final mode = (search['mode'] as String?) ?? 'standard';
      await _bumpWeight(prefs, 'weight_mode_$mode', multiplier, 0.1, 5.0);

      // Engine-Gewicht (welche Such-Engine fuehrte zu Erfolg)
      final engine = (search['engine'] as String?) ?? 'google';
      await _bumpWeight(prefs, 'weight_engine_$engine', multiplier, 0.3, 3.0);

      // Filter-Gewichte
      final sources = (search['sources'] as List<dynamic>?) ?? const <dynamic>[];
      final files = (search['files'] as List<dynamic>?) ?? const <dynamic>[];
      for (final filter in [...sources, ...files]) {
        await _bumpWeight(
            prefs, 'weight_filter_$filter', multiplier, 0.1, 5.0);
      }

      // Keyword-Gewichte (gedaempft, halber Effekt vom Ausgangs-Multiplier)
      final query = (search['query'] as String?) ?? '';
      await _extractAndWeightKeywords(query, multiplier, prefs);

      // Domain-Gewicht: bevorzugte Quellen lernen
      final url = (search['url'] as String?) ?? '';
      final host = _extractHost(url);
      if (host != null) {
        await _bumpWeight(
            prefs, 'weight_domain_$host', multiplier, 0.2, 4.0);
      }
    }

    await searchBox.clear();
    await _logPrivacyAction(
        'Interessen-Modell verfeinert. Verlaufs-Hygiene durchgefuehrt.');
  }

  /// Decay: alle Gewichte 5% Richtung 1.0 schieben.
  /// Verhindert, dass alte Praeferenzen ewig dominieren.
  Future<void> _applyDecay(SharedPreferences prefs) async {
    final keys = prefs.getKeys().where((k) => k.startsWith('weight_')).toList();
    int updated = 0;
    for (final k in keys) {
      final v = prefs.getDouble(k);
      if (v == null) continue;
      final next = v + (1.0 - v) * _decayFactor;
      // nahe 1.0: aufraeumen
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

  Future<void> _bumpWeight(SharedPreferences prefs, String key,
      double multiplier, double min, double max) async {
    final current = prefs.getDouble(key) ?? 1.0;
    await prefs.setDouble(key, (current * multiplier).clamp(min, max));
  }

  Future<void> _logPrivacyAction(String message) async {
    if (!Hive.isBoxOpen(_logBoxName)) return;
    final logBox = Hive.box<dynamic>(_logBoxName);
    await logBox.add(<String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'action': 'interest_model_refinement',
      'message': message,
    });
  }

  List<Map<String, dynamic>> getFeedbackForReview() {
    if (!Hive.isBoxOpen(_feedbackBoxName)) return const <Map<String, dynamic>>[];
    final box = Hive.box<dynamic>(_feedbackBoxName);
    return box.values
        .map((dynamic e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> clearAllFeedback() async {
    if (!Hive.isBoxOpen(_feedbackBoxName)) return;
    await Hive.box<dynamic>(_feedbackBoxName).clear();
  }

  Future<void> _extractAndWeightKeywords(
      String query, double multiplier, SharedPreferences prefs) async {
    // 1. Operatoren rausfiltern, damit z.B. "site:reddit.com" nicht als
    //    Keyword "site" gelernt wird.
    final clean = query
        .replaceAll(RegExp(r'\b(site|inurl|intitle|intext|filetype|ext|before|after|allintitle|allintext|allinurl):\S+'), ' ')
        .replaceAll(RegExp(r'-\S+'), ' ') // Negation entfernen
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .toLowerCase();

    final words = clean
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 3 && !_stopwords.contains(w))
        .toList();

    // Halber Effekt damit Keywords nicht zu schnell extreme Werte annehmen
    final leanMultiplier = 1.0 + (multiplier - 1.0) * 0.5;
    for (final word in words) {
      await _bumpWeight(prefs, 'weight_kw_$word', leanMultiplier, 0.3, 3.0);
    }
    if (kDebugMode) {
      debugPrint('Updated keyword weights: ${words.length} terms');
    }
  }

  String? _extractHost(String url) {
    try {
      final uri = Uri.parse(url);
      // Suchmaschinen-Hosts ueberspringen -> die wollen wir nicht "lernen"
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

  static const Set<String> _stopwords = {
    'der','die','das','und','oder','aber','mit','von','zur','zum','auf',
    'fuer','für','ist','sind','war','wird','werden','haben','hat','sich',
    'dass','weil','wenn','dann','also','noch','nur','auch','als','wie',
    'eine','einen','einem','einer','eines','dem','den','des',
    'with','from','your','have','will','would','about','what','when',
    'where','which','their','they','them','were','been','into','than','that',
    'this','these','those',
  };
}
