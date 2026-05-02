import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'themes_catalog.dart';

/// PrecisionAdvisor — analysiert die lokale Such-Historie + Feedback,
/// um den persoenlichen Stil des Users zu lernen.
///
/// 100% offline, Hive-basiert + SharedPreferences-Gewichte. Kein Byte
/// verlaesst das Geraet.
///
/// Liefert:
///   - bevorzugter Modus (precise/standard/discover/recent)
///   - durchschnittliche Wortzahl bei erfolgreichen Suchen
///   - Top-Themen aus Coach-Choices
///   - Gesamtzufriedenheit (Anteil 'up' an gesamten Bewertungen)
///   - Top-2 bevorzugte Quellen-Filter (weight_filter_* > 1.1)  [NEU]
///   - Label des bevorzugten Coach-Themes (aus ThemesCatalog)   [NEU]
class PrecisionAdvisor {
  static const String _searchBox = 'learning_data';
  static const String _feedbackBox = 'learning_feedback';

  static Future<PrecisionRecommendation> analyze() async {
    if (!Hive.isBoxOpen(_searchBox) || !Hive.isBoxOpen(_feedbackBox)) {
      return PrecisionRecommendation.empty();
    }
    final searches = Hive.box<dynamic>(_searchBox);
    final feedback = Hive.box<dynamic>(_feedbackBox);
    if (searches.isEmpty || feedback.isEmpty) {
      return PrecisionRecommendation.empty();
    }

    // searchId -> rating
    final fbMap = <String, String>{};
    for (final v in feedback.values) {
      if (v is Map &&
          v['search_id'] != null &&
          v['rating'] is String) {
        fbMap[v['search_id'].toString()] = v['rating'] as String;
      }
    }
    if (fbMap.isEmpty) return PrecisionRecommendation.empty();

    int totalUp = 0;
    int totalDown = 0;
    int wordSumUp = 0;
    int wordCountUp = 0;
    final modeStat = <String, _Stat>{};
    final themeStat = <String, _Stat>{};

    for (final k in searches.keys) {
      final s = searches.get(k);
      if (s is! Map) continue;
      final rating = fbMap[k.toString()];
      if (rating == null) continue;

      final mode = (s['mode'] as String?) ?? 'standard';
      final query = (s['query'] as String?) ?? '';

      // Wortzahl: nur "echte" Tokens (keine -term, keine site:x usw.)
      final words = query
          .split(RegExp(r'\s+'))
          .where((w) =>
              w.isNotEmpty &&
              !w.startsWith('-') &&
              !w.contains(':') &&
              !w.startsWith('('))
          .length;

      final ms = modeStat.putIfAbsent(mode, () => _Stat());
      if (rating == 'up') {
        ms.up++;
        totalUp++;
        wordSumUp += words;
        wordCountUp++;
      } else {
        ms.down++;
        totalDown++;
      }

      // Theme aus coach_choices ableiten (falls vorhanden)
      final choices = s['coach_choices'];
      if (choices is List && choices.isNotEmpty) {
        final first = choices.first;
        if (first is Map && first['theme'] is String) {
          final tid = first['theme'] as String;
          final ts = themeStat.putIfAbsent(tid, () => _Stat());
          if (rating == 'up') {
            ts.up++;
          } else {
            ts.down++;
          }
        }
      }
    }

    if ((totalUp + totalDown) == 0) {
      return PrecisionRecommendation.empty();
    }

    // Bester Modus (Score = up - 0.7*down, mind. 1 Bewertung)
    String bestMode = 'standard';
    double bestScore = -double.infinity;
    modeStat.forEach((m, st) {
      final s = st.up - st.down * 0.7;
      if (s > bestScore && (st.up + st.down) >= 1) {
        bestScore = s;
        bestMode = m;
      }
    });

    // Top-Themen (sortiert nach up - down, mind. 1 positiv)
    final themesSorted = themeStat.entries.toList()
      ..sort((a, b) =>
          (b.value.up - b.value.down).compareTo(a.value.up - a.value.down));
    final topThemes = themesSorted
        .where((e) => e.value.up >= 1)
        .take(3)
        .map((e) => e.key)
        .toList();

    final avgWords =
        wordCountUp > 0 ? (wordSumUp / wordCountUp).round() : 0;
    final satisfaction = totalUp / (totalUp + totalDown);

    // --- NEU: Top-2 bevorzugte Quellen-Filter aus SharedPreferences --------
    final topFilterKeys = <String>[];
    try {
      final prefs = await SharedPreferences.getInstance();
      final entries = <MapEntry<String, double>>[];
      for (final key in prefs.getKeys()) {
        if (key.startsWith('weight_filter_')) {
          final val = prefs.getDouble(key) ?? 1.0;
          // Nur statistisch signifikante Praeferenz (> 1.1 = mindestens
          // ein positives Feedback-Signal ueber dem Basis-Gewicht)
          if (val > 1.1) {
            entries.add(
              MapEntry(key.substring('weight_filter_'.length), val),
            );
          }
        }
      }
      entries.sort((a, b) => b.value.compareTo(a.value));
      topFilterKeys.addAll(entries.take(2).map((e) => e.key));
    } catch (e) {
      if (kDebugMode) debugPrint('PrecisionAdvisor: filter read failed: $e');
    }

    // --- NEU: Label des Top-Coach-Themes aus ThemesCatalog -----------------
    final topThemeLabel = topThemes.isNotEmpty
        ? ThemesCatalog.byId(topThemes.first)?.label
        : null;

    return PrecisionRecommendation(
      preferredMode: bestMode,
      avgWordCountSuccess: avgWords,
      topThemes: topThemes,
      overallSatisfaction: satisfaction,
      totalRated: totalUp + totalDown,
      topFilterKeys: topFilterKeys,
      topThemeLabel: topThemeLabel,
    );
  }
}

class _Stat {
  int up = 0;
  int down = 0;
}

class PrecisionRecommendation {
  final String preferredMode;
  final int avgWordCountSuccess;
  final List<String> topThemes;
  final double overallSatisfaction;
  final int totalRated;

  /// Top-2 Quellen-Filter, nach gelerntem Gewicht absteigend.
  /// Leer wenn keine signifikante Praeferenz erkannt (weight <= 1.1).
  final List<String> topFilterKeys;

  /// Human-readable Label des Top-Coach-Themes (aus ThemesCatalog.byId).
  /// null wenn kein Theme-Feedback vorliegt.
  final String? topThemeLabel;

  const PrecisionRecommendation({
    required this.preferredMode,
    required this.avgWordCountSuccess,
    required this.topThemes,
    required this.overallSatisfaction,
    required this.totalRated,
    this.topFilterKeys = const <String>[],
    this.topThemeLabel,
  });

  factory PrecisionRecommendation.empty() => const PrecisionRecommendation(
        preferredMode: 'standard',
        avgWordCountSuccess: 0,
        topThemes: <String>[],
        overallSatisfaction: 0.0,
        totalRated: 0,
        topFilterKeys: <String>[],
        topThemeLabel: null,
      );

  /// Erst ab 3 Bewertungen ist die Empfehlung statistisch sinnvoll.
  bool get hasData => totalRated >= 3;

  /// Einzeilige Zusammenfassung: Modus · Woerter · Zufriedenheit.
  String get summary {
    if (!hasData) return '';
    final pct = (overallSatisfaction * 100).round();
    final modeName = const {
          'precise':  'Praezise',
          'standard': 'Standard',
          'discover': 'Entdecken',
          'recent':   'Aktuell',
        }[preferredMode] ??
        preferredMode;
    return 'Dein Stil: $modeName-Modus · etwa $avgWordCountSuccess Woerter · $pct% Treffer';
  }

  // Human-readable Labels fuer weight_filter_* Keys.
  static const Map<String, String> _filterLabels = {
    'academic':       'Wissenschaft',
    'wikipedia':      'Wikipedia',
    'docs':           'Dokumentation',
    'foren':          'Foren',
    'reddit':         'Reddit',
    'news':           'Nachrichten',
    'offiziell':      'Offizielle Seiten',
    'official':       'Offizielle Seiten',
    'blogs':          'Blogs',
    'shopping':       'Shopping',
    'stellenboersen': 'Stellenboersen',
    'ratgeber':       'Ratgeber',
    'forum':          'Foren',
  };

  /// Komma-getrennte Labels der Top-Filter fuer die UI.
  /// Leer wenn [topFilterKeys] leer.
  String get filterHint {
    if (topFilterKeys.isEmpty) return '';
    return topFilterKeys
        .map((k) => _filterLabels[k] ?? k)
        .join(' · ');
  }
}
