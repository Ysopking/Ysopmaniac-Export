/// Datenmodelle fuer den Such-Coach.
///
/// Themen, Dimensionen, Chips und die User-Auswahl, die in den
/// QueryBuilder einfliesst.
library;

enum ChipKind {
  /// Freier Begriff, der als Token in die Query geht
  term,

  /// Begriff, der als Phrase in Anfuehrungszeichen geht
  phrase,

  /// site:domain.tld
  site,

  /// intitle:wort
  intitle,

  /// after:YYYY-MM-DD (value = Anzahl Tage zurueck)
  after,

  /// Mode-Override: precise|standard|discover|recent
  mode,

  /// -wort (Negation)
  exclude,

  /// User-Eingabe ueber "Eigenes..."
  custom,
}

class CoachChip {
  final String id;
  final String label;
  final String emoji;
  final ChipKind kind;
  final String value;

  const CoachChip({
    required this.id,
    required this.label,
    required this.kind,
    required this.value,
    this.emoji = '',
  });
}

class CoachDimension {
  final String id;
  final String question;
  final List<CoachChip> chips;
  final bool allowCustom;
  final bool multiSelect;

  const CoachDimension({
    required this.id,
    required this.question,
    required this.chips,
    this.allowCustom = true,
    this.multiSelect = false,
  });
}

class CoachTheme {
  final String id;
  final String label;
  final String emoji;
  final List<String> triggerWords;
  final List<CoachDimension> dimensions;

  const CoachTheme({
    required this.id,
    required this.label,
    required this.emoji,
    required this.triggerWords,
    required this.dimensions,
  });
}

/// Eine konkrete User-Auswahl im Coach.
class CoachChoice {
  final String themeId;
  final String dimensionId;
  final String chipId;
  final String label;
  final ChipKind kind;
  final String value;

  const CoachChoice({
    required this.themeId,
    required this.dimensionId,
    required this.chipId,
    required this.label,
    required this.kind,
    required this.value,
  });

  Map<String, dynamic> toJson() => {
        'theme': themeId,
        'dim': dimensionId,
        'chip': chipId,
        'kind': kind.name,
        'value': value,
        'label': label,
      };
}

/// Verdichtete Anreicherung, die der QueryBuilder verarbeitet.
class CoachInjection {
  final List<String> hardTerms;
  final List<String> phrases;
  final List<String> intitles;
  final List<String> sites;
  final List<String> excludes;
  final String? after;
  final String? modeOverride;

  const CoachInjection({
    this.hardTerms = const [],
    this.phrases = const [],
    this.intitles = const [],
    this.sites = const [],
    this.excludes = const [],
    this.after,
    this.modeOverride,
  });

  bool get isEmpty =>
      hardTerms.isEmpty &&
      phrases.isEmpty &&
      intitles.isEmpty &&
      sites.isEmpty &&
      excludes.isEmpty &&
      after == null &&
      modeOverride == null;

  factory CoachInjection.fromChoices(List<CoachChoice> choices) {
    final hardTerms = <String>[];
    final phrases = <String>[];
    final intitles = <String>[];
    final sites = <String>[];
    final excludes = <String>[];
    String? after;
    String? mode;

    for (final c in choices) {
      switch (c.kind) {
        case ChipKind.term:
        case ChipKind.custom:
          if (c.value.contains(' ')) {
            phrases.add(c.value);
          } else {
            hardTerms.add(c.value);
          }
          break;
        case ChipKind.phrase:
          phrases.add(c.value);
          break;
        case ChipKind.site:
          sites.add(c.value);
          break;
        case ChipKind.intitle:
          intitles.add(c.value);
          break;
        case ChipKind.exclude:
          excludes.add(c.value);
          break;
        case ChipKind.after:
          // value = Anzahl Tage, in YYYY-MM-DD umrechnen
          final days = int.tryParse(c.value) ?? 365;
          final cutoff = DateTime.now().subtract(Duration(days: days));
          after =
              '${cutoff.year}-${cutoff.month.toString().padLeft(2, '0')}-${cutoff.day.toString().padLeft(2, '0')}';
          break;
        case ChipKind.mode:
          mode = c.value;
          break;
      }
    }

    return CoachInjection(
      hardTerms: hardTerms,
      phrases: phrases,
      intitles: intitles,
      sites: sites,
      excludes: excludes,
      after: after,
      modeOverride: mode,
    );
  }
}

/// Rueckgabe-Objekt der CoachScreen.
class CoachResult {
  final bool skipped; // User klickte "Direkt suchen"
  final List<CoachChoice> choices;
  final String? overrideQuery; // Manuelle Edit der Vorschau

  const CoachResult({
    this.skipped = false,
    this.choices = const [],
    this.overrideQuery,
  });
}
