/// Stammdaten-Resolver: Wandelt User-Stammdaten + Such-Intent in
/// konkrete Query-Anreicherungen um.
///
/// Eingabe:
///   - Settings-Map (employmentType, beruf, plz, language, country, jahr)
///   - WAS- und WARUM-Text (zur Intent-Erkennung)
///
/// Ausgabe (StammdatenContext):
///   - softTerms:        Begriffe, die per OR-Boost optional eingefuegt werden
///   - hardTerms:        Begriffe, die zwingend in die Query gehoeren (z.B. PLZ
///                       bei Lokal-Intent)
///   - preferredSources: Quellen-Keys, die bevorzugt werden (Soft-Bias wenn
///                       der User keine eigene Quellen-Auswahl getroffen hat)
///   - languageHint:     z.B. 'lang_de' fuer Google `lr=`
///
/// Idee: Stammdaten werden NICHT blind in jede Query gepfeffert — das
/// vermuellt das Ergebnis. Stattdessen wird Intent erkannt und nur dort
/// angereichert, wo es sinnvoll ist.
library;

class StammdatenContext {
  final List<String> softTerms;
  final List<String> hardTerms;
  final List<String> preferredSources;
  final String? languageHint;
  final bool boostRecent;

  const StammdatenContext({
    this.softTerms = const [],
    this.hardTerms = const [],
    this.preferredSources = const [],
    this.languageHint,
    this.boostRecent = false,
  });
}

class StammdatenResolver {
  /// Empfohlene Quellen pro Beschaeftigungstyp (Soft-Bias).
  static const Map<String, List<String>> _employmentSourcePresets = {
    'student': ['academic', 'wikipedia', 'docs'],
    'vollzeit': ['docs', 'foren', 'blogs'],
    'teilzeit': ['docs', 'foren', 'blogs'],
    'rentner': ['wikipedia', 'news', 'offiziell'],
    'erwerbslos': ['offiziell', 'foren', 'news'],
  };

  /// Intent-Trigger-Worte: WAS oder WARUM enthaelt einen dieser Begriffe?
  static const List<String> _locationIntentWords = [
    'regional', 'lokal', 'lokales', 'naehe', 'nähe', 'nahe', 'umgebung',
    'vor ort', 'in meiner stadt', 'in meiner region', 'oertlich', 'örtlich',
    'umkreis', 'plz', 'postleitzahl',
  ];
  static const List<String> _jobIntentWords = [
    'job', 'jobs', 'karriere', 'beruf', 'beruflich', 'arbeit', 'stelle',
    'stellenanzeige', 'bewerbung', 'lebenslauf', 'cv', 'gehalt',
    'arbeitgeber', 'arbeitnehmer',
  ];
  static const List<String> _academicIntentWords = [
    'studie', 'studien', 'forschung', 'paper', 'thesis', 'arbeit',
    'literatur', 'wissenschaft', 'journal', 'doi', 'meta-analyse',
    'systematic review', 'fakultaet', 'fakultät', 'professor',
  ];
  static const List<String> _newsIntentWords = [
    'aktuell', 'heute', 'gestern', 'breaking', 'neueste', 'nachricht',
    'nachrichten', 'meldung', 'news',
  ];

  StammdatenContext resolve({
    required String what,
    required String why,
    required Map<String, dynamic> settings,
  }) {
    final softTerms = <String>[];
    final hardTerms = <String>[];
    final preferredSources = <String>[];

    final fullText = '${what.toLowerCase()} ${why.toLowerCase()}';
    final hasLocation = _containsAny(fullText, _locationIntentWords);
    final hasJob = _containsAny(fullText, _jobIntentWords);
    final hasAcademic = _containsAny(fullText, _academicIntentWords);
    final hasNews = _containsAny(fullText, _newsIntentWords);

    final employmentType =
        ((settings['employmentType'] as String?) ?? 'student').trim();
    final beruf = ((settings['beruf'] as String?) ?? '').trim();
    final plz = ((settings['plz'] as String?) ?? '').trim();
    final language = ((settings['language'] as String?) ?? 'de').trim();
    final country = ((settings['country'] as String?) ?? 'de').trim();
    final jahr = (settings['jahr'] as int?) ?? 1990;

    // 1) Beschaeftigungs-Preset als Quellen-Bias
    final preset = _employmentSourcePresets[employmentType];
    if (preset != null) {
      preferredSources.addAll(preset);
    }

    // 2) Job-Intent: Jobrichtung + employmentType-Marker zwingend rein
    if (hasJob) {
      if (beruf.isNotEmpty) {
        hardTerms.add(beruf.contains(' ') ? '"$beruf"' : beruf);
      }
      // Vollzeit/Teilzeit-Marker hilft bei Stellenanzeigen
      if (employmentType == 'vollzeit' || employmentType == 'teilzeit') {
        hardTerms.add(employmentType);
      }
    } else if (beruf.isNotEmpty) {
      // Sonst nur als ganz weicher Boost (laesst Google entscheiden)
      softTerms.add(beruf.toLowerCase().split(' ').first);
    }

    // 3) Lokal-Intent: PLZ + Land in die Query
    if (hasLocation && plz.isNotEmpty && plz != '0') {
      hardTerms.add(plz);
      // Bundeslaender-/Stadt-Hint via Country-Code
      hardTerms.add(country == 'de' ? 'Deutschland' : country.toUpperCase());
    }

    // 4) Academic-Intent: zusaetzlich Academic-Quellen vorne
    if (hasAcademic) {
      preferredSources.insertAll(0, ['academic', 'docs']);
      // Studenten zusaetzlich Wiki-bias raus, weil Studien wichtiger
    }

    // 5) News-Intent
    if (hasNews) {
      preferredSources.insertAll(0, ['news']);
    }

    // 6) Senioren / Rentner: Klartext bevorzugen, Foren raus
    if (employmentType == 'rentner') {
      preferredSources.removeWhere((s) => s == 'foren' || s == 'reddit');
    }

    // 7) Sprache als Hint fuer Google `lr=`
    final languageHint = (language == 'de' || language == 'en')
        ? 'lang_$language'
        : null;

    // 8) Aktualitaets-Boost: News-Intent ODER User <30 Jahre
    final age = DateTime.now().year - jahr;
    final boostRecent = hasNews || (age >= 0 && age <= 30);

    // Doppelte preferredSources entfernen, Reihenfolge erhalten
    final dedupedSources = <String>{};
    final orderedSources = <String>[];
    for (final s in preferredSources) {
      if (dedupedSources.add(s)) orderedSources.add(s);
    }

    return StammdatenContext(
      softTerms: softTerms,
      hardTerms: hardTerms,
      preferredSources: orderedSources,
      languageHint: languageHint,
      boostRecent: boostRecent,
    );
  }

  bool _containsAny(String haystack, List<String> needles) {
    for (final n in needles) {
      if (haystack.contains(n)) return true;
    }
    return false;
  }
}

