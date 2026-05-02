import 'coach_models.dart';

/// Persoenliche Anpassung fuer den QualityEstimator.
/// Wird aus SharedPreferences (weight_mode_*, Feedback-Statistik) befuellt.
class QualityPersonalization {
  /// Anteil positiver Bewertungen (0.0–1.0). Basis: 0.5 (unbekannt).
  final double overallSatisfaction;

  /// Der bevorzugte Modus des Users (highest weight_mode_* key).
  final String preferredMode;

  /// Der aktuell vom Coach gewahlte Modus.
  final String currentMode;

  const QualityPersonalization({
    this.overallSatisfaction = 0.5,
    this.preferredMode = 'standard',
    this.currentMode = 'standard',
  });
}

/// Schaetzt die Qualitaet einer geplanten Suche (0–100) plus Hints.
///
/// Heuristik (additiv, geclamped):
///   - Basis: 30
///   - WAS hat Inhalt: +15
///   - WARUM hat Inhalt: +10  (Penalty nur wenn overallSatisfaction <= 0.75)
///   - Pro Coach-Chip: +6 (max 30)
///   - Phrase erkannt (in Quotes): +5
///   - Operator vorhanden (site:/intitle:/after:): +10
///   - Bevorzugter Modus aktiv: +5
///   - Keine Konflikte: +5
///   - Konflikt erkannt: -15
///   - WAS zu kurz (<3 Zeichen): -20
///   - Zu viele Operatoren (>8): -15
class QualityResult {
  final int score;
  final List<String> positiveHints;
  final List<String> warnings;
  const QualityResult(this.score, this.positiveHints, this.warnings);
}

class QualityEstimator {
  static QualityResult estimate({
    required String what,
    required String why,
    required List<CoachChoice> choices,
    QualityPersonalization? personalization,
  }) {
    final p = personalization ?? const QualityPersonalization();
    int score = 30;
    final pos = <String>[];
    final warn = <String>[];

    final whatTrim = what.trim();
    final whyTrim = why.trim();

    if (whatTrim.length < 3) {
      score -= 20;
      warn.add('Suchbegriff zu kurz');
    } else {
      score += 15;
      pos.add('Suchbegriff gesetzt');
    }

    if (whyTrim.isNotEmpty) {
      score += 10;
      pos.add('Kontext (Warum) gegeben');
    } else {
      // WARUM-Penalty nur wenn User historisch noch keinen stabilen
      // Erfolgs-Stil ohne Kontext entwickelt hat.
      // Wer ohne Kontext konsistent gute Ergebnisse bekommt
      // (overallSatisfaction > 0.75) — kein Warn, kein Penalty.
      if (p.overallSatisfaction <= 0.75) {
        warn.add('Kein Kontext angegeben — Coach hilft beim Schaerfen');
      }
    }

    final chipCount = choices.length;
    if (chipCount > 0) {
      score += (chipCount * 6).clamp(0, 30);
      pos.add('$chipCount Verfeinerung${chipCount == 1 ? "" : "en"} aktiv');
    }

    if (whatTrim.contains('"')) {
      score += 5;
      pos.add('Phrase exakt');
    }

    final hasSiteOp = choices.any((c) => c.kind == ChipKind.site);
    final hasTitleOp = choices.any((c) => c.kind == ChipKind.intitle);
    final hasAfter = choices.any((c) => c.kind == ChipKind.after);
    if (hasSiteOp || hasTitleOp || hasAfter) {
      score += 10;
      pos.add('Smart-Operatoren genutzt');
    }

    // Personalisierter Mode-Bonus: User sucht bevorzugt in diesem Modus und
    // der Coach zeigt denselben → "Im Wohlfuehl-Modus"
    if (p.preferredMode.isNotEmpty &&
        p.preferredMode == p.currentMode &&
        p.preferredMode != 'standard') {
      score += 5;
      pos.add('Bevorzugter Modus aktiv');
    }

    // Konflikt-Detektion: Reddit + Wissenschaft
    final sites = choices
        .where((c) => c.kind == ChipKind.site)
        .map((c) => c.value.toLowerCase())
        .join(' ');
    final hasReddit = sites.contains('reddit.com');
    final hasScholar = sites.contains('scholar.google') ||
        sites.contains('arxiv.org') ||
        sites.contains('cochrane') ||
        sites.contains('pubmed');
    if (hasReddit && hasScholar) {
      score -= 15;
      warn.add('Reddit + wissenschaftliche Quelle passt selten zusammen');
    } else {
      score += 5;
    }

    if (chipCount > 8) {
      score -= 15;
      warn.add('Zu viele Verfeinerungen — Google ignoriert evtl. einige');
    }

    score = score.clamp(0, 100);
    return QualityResult(score, pos, warn);
  }
}
