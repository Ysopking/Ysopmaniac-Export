import 'package:hive/hive.dart';

/// PrecisionAdvisor — analysiert die lokale Such-Historie + Feedback,
/// um den persoenlichen Stil des Users zu lernen.
///
/// 100% offline, Hive-basiert, verschluesselt. Kein Byte verlaesst das Geraet.
///
/// Liefert:
///   - bevorzugter Modus (precise/standard/discover/recent)
///   - durchschnittliche Wortzahl bei erfolgreichen Suchen
///   - Top-Themen aus Coach-Choices
///   - Gesamtzufriedenheit (Anteil 'up' an gesamten Bewertungen)
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

    // Top-Themen
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

    return PrecisionRecommendation(
      preferredMode: bestMode,
      avgWordCountSuccess: avgWords,
      topThemes: topThemes,
      overallSatisfaction: satisfaction,
      totalRated: totalUp + totalDown,
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

  const PrecisionRecommendation({
    required this.preferredMode,
    required this.avgWordCountSuccess,
    required this.topThemes,
    required this.overallSatisfaction,
    required this.totalRated,
  });

  factory PrecisionRecommendation.empty() => const PrecisionRecommendation(
        preferredMode: 'standard',
        avgWordCountSuccess: 0,
        topThemes: const <String>[],
        overallSatisfaction: 0.0,
        totalRated: 0,
      );

  /// Erst ab 3 Bewertungen ist die Empfehlung statistisch sinnvoll.
  bool get hasData => totalRated >= 3;

  String get summary {
    if (!hasData) return '';
    final pct = (overallSatisfaction * 100).round();
    final modeName = const {
          'precise': 'Praezise',
          'standard': 'Standard',
          'discover': 'Entdecken',
          'recent': 'Aktuell',
        }[preferredMode] ??
        preferredMode;
    return 'Dein Stil: $modeName-Modus · etwa $avgWordCountSuccess Woerter · $pct% Treffer';
  }
}
