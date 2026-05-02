import 'package:shared_preferences/shared_preferences.dart';
import 'coach_models.dart';
import 'themes_catalog.dart';

/// Erkennt anhand des Such-Texts das passende Coach-Thema.
///
/// Strategie:
///   1) Trigger-Wort-Match (exakter Substring, Reihenfolge im Katalog = Prioritaet)
///   2) Personalisierter Fallback: weight_theme_* aus SharedPreferences —
///      hoechstgewichtetes Theme mit Gewicht > 1.1 gewinnt
///   3) Letzter Fallback: "allgemein"
class ThemeDetector {
  /// Sync-Variante. [weights] kann optional vorgeladen uebergeben werden
  /// (z.B. aus SharedPreferences) um den personalisierten Fallback zu nutzen.
  static CoachTheme detect(String what, String why,
      {Map<String, double>? weights}) {
    final hay = '${what.toLowerCase()} ${why.toLowerCase()}';
    for (final theme in ThemesCatalog.all) {
      for (final trigger in theme.triggerWords) {
        if (hay.contains(trigger)) return theme;
      }
    }
    // Personalisierter Fallback — nur wenn Gewichte vorliegen.
    // "allgemein" wird bewusst uebersprungen: es ist der neutrale Fallback,
    // kein gelerntes Thema.
    if (weights != null && weights.isNotEmpty) {
      CoachTheme? best;
      double bestW = 1.1; // Mindestschwelle: mind. ein positives Signal
      for (final theme in ThemesCatalog.all) {
        if (theme.id == 'allgemein') continue;
        final w = weights['weight_theme_${theme.id}'] ?? 1.0;
        if (w > bestW) {
          bestW = w;
          best = theme;
        }
      }
      if (best != null) return best;
    }
    return ThemesCatalog.byId('allgemein')!;
  }

  /// Async-Variante: laedt weight_theme_*-Keys aus SharedPreferences und
  /// wendet personalisierten Fallback an.
  static Future<CoachTheme> detectAsync(String what, String why) async {
    final prefs = await SharedPreferences.getInstance();
    final weights = <String, double>{};
    for (final k in prefs.getKeys()) {
      if (k.startsWith('weight_theme_')) {
        weights[k] = prefs.getDouble(k) ?? 1.0;
      }
    }
    return detect(what, why, weights: weights);
  }
}
