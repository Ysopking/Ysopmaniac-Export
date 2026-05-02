import 'coach_models.dart';

/// Schaetzt die Qualitaet einer geplanten Suche (0-100) plus Hints.
///
/// Heuristik (additiv, geclamped):
///   - Basis: 30
///   - WAS hat Inhalt: +15
///   - WARUM hat Inhalt: +10
///   - Pro Coach-Chip: +6 (max 30)
///   - Phrase erkannt (in Quotes): +5
///   - Operator vorhanden (site:/intitle:/after:): +10
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
  }) {
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
      warn.add('Kein Kontext angegeben — Coach hilft beim Schärfen');
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
