/// Stammdaten-Resolver: Wandelt User-Stammdaten + Such-Intent in
/// konkrete Query-Anreicherungen um.
///
/// Eingabe:
///   - Settings-Map (employmentType, beruf, plz, language, country, jahr)
///   - WAS- und WARUM-Text (zur Intent-Erkennung)
///   - employmentWeight: gelerntes Gewicht aus SharedPreferences
///                       (weight_employment_<type>, Default 1.0)
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
  /// Reihenfolge = Prioritaet. Wird durch employmentWeight skaliert:
  ///   < 0.7  → 0 Quellen (Preset ignoriert)
  ///   0.7–1.2 → erste 2 Quellen
  ///   > 1.2  → alle Quellen des Presets
  ///
  /// Aenderungen ggue. v1:
  ///   - teilzeit: eigenes Profil (news + offiziell + ratgeber) statt = vollzeit
  ///   - erwerbslos: stellenboersen an erster Stelle
  static const Map<String, List<String>> _employmentSourcePresets = {
    'student':    ['academic', 'wikipedia', 'docs'],
    'vollzeit':   ['docs', 'foren', 'blogs'],
    'teilzeit':   ['news', 'offiziell', 'blogs'],
    'rentner':    ['wikipedia', 'news', 'offiziell'],
    'erwerbslos': ['stellenboersen', 'offiziell', 'foren', 'news'],
  };

  /// Stellenbörsen-spezifische Job-Intent-Trigger nur fuer erwerbslos
  static const List<String> _jobSearchIntentWords = [
    'job', 'jobs', 'stelle', 'stellen', 'stellenanzeige', 'stellenanzeigen',
    'bewerbung', 'bewerben', 'lebenslauf', 'cv', 'arbeit', 'arbeitssuche',
    'karriere', 'arbeitsamt', 'arbeitsagentur', 'foerderung',
  ];

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

  /// Intent-Signalworte fuer Finanz-Kontext (Sozialleistungen, Steuern,
  /// Rente, Mietrecht, Investieren, Familienrecht).
  static const List<String> _finanzIntentWords = [
    'geld', 'euro', 'kosten', 'preis', 'guenstig', 'günstig', 'sparen',
    'foerderung', 'förderung', 'leistung', 'antrag', 'sozial', 'steuer',
    'steuern', 'rente', 'miete', 'kredit', 'budget', 'haushalt', 'finanz',
    'finanzen', 'versicherung', 'gehalt', 'einkommen', 'schulden',
    'investieren', 'anlage', 'etf', 'aktien', 'krypto', 'riester',
    'buergergeld', 'bürgergeld', 'kindergeld', 'wohngeld', 'unterhalt',
    'sorgerecht', 'erbrecht', 'mietvertrag', 'nebenkosten',
  ];

  /// Intent-Signalworte fuer Bildungs-Kontext (Bewerbung, Studium,
  /// Weiterbildung, Selbststaendigkeit, Kinder).
  static const List<String> _bildungIntentWords = [
    'lernen', 'lerntipp', 'kurs', 'ausbildung', 'studium', 'studieren',
    'weiterbildung', 'schule', 'schulisch', 'bewerbung', 'bewerben',
    'lebenslauf', 'zertifikat', 'nachhilfe', 'hausaufgaben', 'prüfung',
    'pruefung', 'umschulung', 'freelance', 'freiberuflich', 'gruendung',
    'gründung', 'startup', 'hochschule', 'bafoeg', 'bafög', 'lernmethode',
    'onlinekurs', 'zertifikat', 'bildung', 'abschluss', 'quereinstieg',
  ];

  /// Bevorzugte Quellen pro Interesse-Top-Kategorie.
  /// Werden NUR hinzugefuegt, wenn ein passender Intent erkannt wird.
  static const Map<String, List<String>> _interestSources = {
    'finanzen':      ['offiziell', 'ratgeber'],
    'bildung':       ['academic', 'docs', 'ratgeber'],
    'sport':         ['ratgeber', 'blogs'],
    'kochen':        ['ratgeber', 'blogs'],
    'tech':          ['docs', 'foren', 'blogs'],
    'reisen':        ['ratgeber', 'blogs'],
    'wissenschaft':  ['academic', 'docs'],
    'mathe':         ['academic', 'docs'],
    'sprachen':      ['academic', 'ratgeber'],
    'gaming':        ['foren', 'blogs'],
    'auto':          ['ratgeber', 'foren'],
    'garten':        ['ratgeber', 'blogs'],
    'musik':         ['blogs'],
    'film':          ['blogs'],
  };

  /// SoftTerms pro Interesse-Top-Kategorie (werden bei Intent-Treffer
  /// als optionaler Kontext-Boost in die Query injiziert).
  static const Map<String, List<String>> _interestSoftTerms = {
    'finanzen': ['Förderung', 'offiziell'],
    'bildung':  ['Kurs', 'Weiterbildung'],
    'sport':    ['Training', 'Übungen'],
    'kochen':   ['Rezept'],
    'tech':     ['Tutorial', 'Anleitung'],
    'reisen':   ['Reisebericht', 'Erfahrung'],
    'wissenschaft': ['Studie', 'Forschung'],
  };

  StammdatenContext resolve({
    required String what,
    required String why,
    required Map<String, dynamic> settings,
    double employmentWeight = 1.0,
    List<String> interests = const [],
  }) {
    final softTerms = <String>[];
    final hardTerms = <String>[];
    final preferredSources = <String>[];

    final fullText = '${what.toLowerCase()} ${why.toLowerCase()}';
    final hasLocation = _containsAny(fullText, _locationIntentWords);
    final hasJob = _containsAny(fullText, _jobIntentWords);
    final hasAcademic = _containsAny(fullText, _academicIntentWords);
    final hasNews = _containsAny(fullText, _newsIntentWords);
    final hasJobSearch = _containsAny(fullText, _jobSearchIntentWords);
    final hasFinanz  = _containsAny(fullText, _finanzIntentWords);
    final hasBildung = _containsAny(fullText, _bildungIntentWords);

    final employmentType =
        ((settings['employmentType'] as String?) ?? 'student').trim();
    final beruf = ((settings['beruf'] as String?) ?? '').trim();
    final plz = ((settings['plz'] as String?) ?? '').trim();
    final language = ((settings['language'] as String?) ?? 'de').trim();
    final country = ((settings['country'] as String?) ?? 'de').trim();
    final jahr = (settings['jahr'] as int?) ?? 1990;

    // 1) Beschaeftigungs-Preset als Quellen-Bias (skaliert durch employmentWeight)
    final preset = _employmentSourcePresets[employmentType];
    if (preset != null && employmentWeight >= 0.7) {
      // Anzahl der aktivierten Preset-Quellen haengt vom gelernten Gewicht ab
      final count = employmentWeight >= 1.4
          ? preset.length          // alles aktivieren
          : (employmentWeight >= 1.0 ? 2 : 1); // Standard oder reduziert
      preferredSources.addAll(preset.take(count));
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

    // 3) Erwerbslos + Job-Suche-Intent: Stellenboersen explizit nach vorne
    if (employmentType == 'erwerbslos' && hasJobSearch) {
      if (!preferredSources.contains('stellenboersen')) {
        preferredSources.insert(0, 'stellenboersen');
      }
      // Arbeitsagentur-Tipp als SoftTerm
      softTerms.add('Stellenanzeige');
    }

    // 4) Lokal-Intent: PLZ + Land in die Query
    if (hasLocation && plz.isNotEmpty && plz != '0') {
      hardTerms.add(plz);
      // Bundeslaender-/Stadt-Hint via Country-Code
      hardTerms.add(country == 'de' ? 'Deutschland' : country.toUpperCase());
    }

    // 5) Academic-Intent: zusaetzlich Academic-Quellen vorne
    if (hasAcademic) {
      preferredSources.insertAll(0, ['academic', 'docs']);
    }

    // 6) News-Intent
    if (hasNews) {
      preferredSources.insertAll(0, ['news']);
    }

    // 7) Senioren / Rentner: Klartext bevorzugen, Foren raus
    if (employmentType == 'rentner') {
      preferredSources.removeWhere((s) => s == 'foren' || s == 'reddit');
    }

    // 8) Sprache als Hint fuer Google `lr=`
    final languageHint = (language == 'de' || language == 'en')
        ? 'lang_$language'
        : null;

    // 9) Aktualitaets-Boost: News-Intent ODER User <30 Jahre
    final age = DateTime.now().year - jahr;
    final boostRecent = hasNews || (age >= 0 && age <= 30);

    // 10) Interesse-basierte Anreicherung (intent-sensitiv)
    //
    //  • Finanzen: softTerms + offiziell/ratgeber-Quellen bei Finanz-Intent
    //  • Bildung:  academic/docs/ratgeber bei Bildungs-Intent
    //  • Alle anderen Kategorien: nur Quellen-Bias, keine hartcodierten Terme
    //  • Sub-Kategorie-spezifisch: Soziales → "Förderung" + "Antrag" als
    //    Soft-Hint, wenn es nicht schon aus Employment-Seed kommt
    if (interests.isNotEmpty) {
      // Top-Level-Kategorien dedupliziert extrahieren
      final topCats = interests
          .map((p) => p.split('/').first)
          .toSet();

      for (final cat in topCats) {
        final intentMatches = switch (cat) {
          'finanzen' => hasFinanz,
          'bildung'  => hasBildung,
          _          => _containsAny(
              fullText,
              // Faellt-through: immer aktivieren (weicher Quellen-Bias)
              [cat, cat.substring(0, cat.length > 4 ? 4 : cat.length)],
            ),
        };
        if (!intentMatches) continue;

        // Quellen-Bias hinzufuegen
        final sources = _interestSources[cat];
        if (sources != null) preferredSources.addAll(sources);

        // SoftTerms hinzufuegen (falls Kategorie einen Eintrag hat)
        final terms = _interestSoftTerms[cat];
        if (terms != null) {
          for (final t in terms) {
            if (!softTerms.contains(t)) softTerms.add(t);
          }
        }
      }

      // Sub-Kategorie-spezifische Anreicherung
      // Muster: finanzen/soziales/* → Förderung + Antrag sofern Finanz-Intent
      if (hasFinanz) {
        final hasSoziales  = interests.any((p) => p.startsWith('finanzen/soziales/'));
        final hasSteuern   = interests.any((p) => p.startsWith('finanzen/steuern/'));
        final hasRente     = interests.any((p) => p.startsWith('finanzen/rente/'));
        final hasMietrecht = interests.any((p) => p.startsWith('finanzen/mietrecht/'));

        if (hasSoziales && !softTerms.contains('Antrag')) {
          softTerms.add('Antrag');
        }
        if (hasSteuern && !softTerms.contains('Finanzamt')) {
          softTerms.add('Finanzamt');
        }
        if (hasRente && !softTerms.contains('Rentenversicherung')) {
          softTerms.add('Rentenversicherung');
        }
        if (hasMietrecht && !softTerms.contains('Mieterbund')) {
          softTerms.add('Mieterbund');
        }
      }
      if (hasBildung) {
        final hasWeiterbildung = interests.any(
            (p) => p.startsWith('bildung/weiterbildung/'));
        final hasBewerbung = interests.any(
            (p) => p.startsWith('bildung/bewerbung/'));
        if (hasWeiterbildung && !softTerms.contains('Bildungsgutschein')) {
          softTerms.add('Bildungsgutschein');
        }
        if (hasBewerbung && !softTerms.contains('Vorlage')) {
          softTerms.add('Vorlage');
        }
      }
    }

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
