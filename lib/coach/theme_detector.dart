import 'coach_models.dart';
import 'themes_catalog.dart';

/// Erkennt anhand des Such-Texts das passende Coach-Thema.
///
/// Strategie:
///   1) Trigger-Wort-Match (jedes Thema hat Trigger-Liste, exakter Substring)
///   2) Erstes Match gewinnt — Reihenfolge im Katalog ist Prioritaet
///   3) Fallback "allgemein" wenn nichts matcht
class ThemeDetector {
  static CoachTheme detect(String what, String why) {
    final hay = '${what.toLowerCase()} ${why.toLowerCase()}';
    for (final theme in ThemesCatalog.all) {
      for (final trigger in theme.triggerWords) {
        if (hay.contains(trigger)) return theme;
      }
    }
    return ThemesCatalog.byId('allgemein')!;
  }
}
