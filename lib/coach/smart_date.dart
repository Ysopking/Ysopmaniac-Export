/// Liefert je nach erkanntem Intent einen passenden after:DATE-Operator.
///
/// Logik (ueberschreibt nichts wenn der User selbst bereits einen
/// after-Chip im Coach gesetzt hat — dann uebernimmt CoachInjection):
///   - News-Intent          -> 90 Tage
///   - Studien/Wissenschaft -> 5 Jahre
///   - Code/Software-Bug    -> 1 Jahr
///   - Recht/Gesetz         -> kein Filter (Gesetze haben oft alte Quellen)
///   - Definition           -> kein Filter
///   - Default              -> kein Filter
class SmartDate {
  static const _newsWords = [
    'aktuell', 'heute', 'gestern', 'breaking', 'neueste', 'nachricht',
    'meldung', 'news',
  ];
  static const _scienceWords = [
    'studie', 'studien', 'forschung', 'paper', 'thesis', 'meta-analyse',
    'systematic', 'cochrane',
  ];
  static const _codeWords = [
    'fehler', 'error', 'bug', 'crash', 'install', 'update', 'version',
    'release',
  ];
  static const _legalWords = [
    'gesetz', 'paragraph', 'urteil', 'rechtsprechung', 'bgb', 'stgb',
  ];
  static const _definitionWords = [
    'was ist', 'definition', 'bedeutung', 'wikipedia',
  ];

  /// Gibt die optimalen Tage zurueck oder null fuer kein Datums-Filter.
  static int? recommendDaysBack(String what, String why) {
    final hay = '${what.toLowerCase()} ${why.toLowerCase()}';
    if (_anyMatch(hay, _legalWords)) return null;
    if (_anyMatch(hay, _definitionWords)) return null;
    if (_anyMatch(hay, _newsWords)) return 90;
    if (_anyMatch(hay, _scienceWords)) return 365 * 5;
    if (_anyMatch(hay, _codeWords)) return 365;
    return null;
  }

  static String? formatAfterOperator(String what, String why) {
    final days = recommendDaysBack(what, why);
    if (days == null) return null;
    final cutoff = DateTime.now().subtract(Duration(days: days));
    return 'after:${cutoff.year}-${cutoff.month.toString().padLeft(2, '0')}-${cutoff.day.toString().padLeft(2, '0')}';
  }

  static bool _anyMatch(String hay, List<String> needles) {
    for (final n in needles) {
      if (hay.contains(n)) return true;
    }
    return false;
  }
}
