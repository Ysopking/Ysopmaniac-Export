/// Stammdaten-Resolver v2: Spec-konforme, beschaeftigungstyp-spezifische
/// Query-Anreicherung.
///
/// Neu in v2 (basierend auf Produkt-Spec):
///   - excludeDomains:  -site: Ausschluesse (Rentner: Pinterest/TikTok;
///                      Vollzeit: gutefrage.net; Teilzeit: Content-Farmen)
///   - dateAfter:       after:YYYY-MM-DD fuer Vollzeit-Aktualitaet
///   - preferIntitle:   intitle: fuer Top-Keyword (Vollzeit)
///   - fileTypeHints:   filetype:pdf/doc (Student: PDF; Erwerbslos: PDF+DOC)
///   - trustDomains:    Rentner medizinisch/finanziell → stiftung-warentest etc.
library;

class StammdatenContext {
  final List<String> softTerms;
  final List<String> hardTerms;
  final List<String> preferredSources;
  final List<String> excludeDomains;
  final List<String> trustDomains;
  final List<String> fileTypeHints;
  final String? languageHint;
  final String? dateAfter;
  final bool boostRecent;
  final bool preferIntitle;

  const StammdatenContext({
    this.softTerms = const [],
    this.hardTerms = const [],
    this.preferredSources = const [],
    this.excludeDomains = const [],
    this.trustDomains = const [],
    this.fileTypeHints = const [],
    this.languageHint,
    this.dateAfter,
    this.boostRecent = false,
    this.preferIntitle = false,
  });
}

class StammdatenResolver {
  // ========== Quellen-Presets (Reihenfolge = Prioritaet) ==========

  /// Skalierung durch employmentWeight:
  ///   < 0.7  → 0 Quellen
  ///   0.7–1.2 → erste 2 Quellen
  ///   ≥ 1.2  → alle Quellen
  static const Map<String, List<String>> _employmentSourcePresets = {
    'student':    ['academic', 'docs', 'wikipedia'],
    'vollzeit':   ['docs', 'foren', 'blogs'],
    'teilzeit':   ['reddit', 'foren', 'news', 'offiziell'],
    'rentner':    ['wikipedia', 'offiziell', 'news'],
    'erwerbslos': ['stellenboersen', 'offiziell', 'foren'],
  };

  // ========== Ausschluss-Domains pro Beschaeftigungstyp ==========

  /// Rentner: Schutzwall gegen Social-Media-Spam und Scam-Seiten
  static const List<String> _rentnerExclusions = [
    'pinterest.de', 'pinterest.com', 'pinterest.at', 'pinterest.ch',
    'tiktok.com', 'instagram.com', 'twitter.com', 'x.com',
    'facebook.com', 'snapchat.com',
    // SEO-Spam und dubiose Gesundheits-Seiten
    'homeopathy.com', 'naturheilkunde.de',
  ];

  /// Vollzeit: Gutefrage + langsamer Hobbyisten-Content
  static const List<String> _vollzeitExclusions = [
    'gutefrage.net', 'wer-weiss-was.de', 'gute-frage.net',
    'pinterest.de', 'pinterest.com',
  ];

  /// Teilzeit: reine Content-Farmen und Click-Bait-Seiten
  static const List<String> _teilzeitExclusions = [
    'pinterest.de', 'pinterest.com',
    'gofeminin.de', 'desired.de', 'stylebook.de',
  ];

  /// Erwerbslos: Coaching-Scams und unseriöse Kursanbieter
  static const List<String> _erwerbslosExclusions = [
    'pinterest.de', 'pinterest.com',
    'geld-verdienen-sofort.de',
  ];

  // ========== Trust-Domains fuer Rentner (Medizin + Finanzen) ==========

  static const List<String> _rentnerMedicalTrustDomains = [
    'stiftung-warentest.de', 'apotheken-umschau.de', 'bund.de',
    'gesundheitsministerium.de', 'rki.de', 'bzga.de',
    'krankenkasse.de', 'vdek.com',
  ];

  static const List<String> _rentnerFinancialTrustDomains = [
    'stiftung-warentest.de', 'bafin.de', 'vzbv.de',
    'verbraucherzentrale.de', 'bundesbank.de', 'bund.de',
  ];

  // ========== Intent-Trigger ==========

  static const List<String> _locationIntentWords = [
    'regional', 'lokal', 'naehe', 'nähe', 'nahe', 'umgebung',
    'vor ort', 'in meiner stadt', 'in meiner region', 'oertlich',
    'umkreis', 'plz', 'postleitzahl', 'lieferung', 'abholung',
  ];
  static const List<String> _jobIntentWords = [
    'job', 'jobs', 'karriere', 'beruf', 'arbeit', 'stelle',
    'stellenanzeige', 'bewerbung', 'lebenslauf', 'cv', 'gehalt',
  ];
  static const List<String> _jobSearchIntentWords = [
    'job', 'jobs', 'stelle', 'stellen', 'bewerbung', 'bewerben',
    'lebenslauf', 'cv', 'arbeitssuche', 'karriere', 'arbeitsamt',
    'foerderung', 'qualifikation', 'weiterbildung',
  ];
  static const List<String> _academicIntentWords = [
    'studie', 'studien', 'forschung', 'paper', 'thesis', 'arbeit',
    'literatur', 'wissenschaft', 'journal', 'doi', 'meta-analyse',
    'skript', 'vorlesung', 'hausarbeit', 'facharbeit', 'quelle',
  ];
  static const List<String> _newsIntentWords = [
    'aktuell', 'heute', 'gestern', 'breaking', 'neueste', 'nachricht',
    'nachrichten', 'meldung', 'news', 'aktuelles',
  ];
  static const List<String> _medicalIntentWords = [
    'gesundheit', 'krankheit', 'medikament', 'arzt', 'symptom',
    'therapie', 'behandlung', 'diagnose', 'impfung', 'allergie',
    'apotheke', 'rezept', 'nebenwirkung', 'pille', 'tablette',
  ];
  static const List<String> _financialIntentWords = [
    'geld', 'kredit', 'zinsen', 'bank', 'konto', 'anlage', 'aktie',
    'rente', 'pension', 'versicherung', 'steuern', 'finanz',
    'betrug', 'phishing', 'scam',
  ];
  static const List<String> _cvIntentWords = [
    'lebenslauf', 'cv', 'vorlage', 'template', 'muster',
    'bewerbungsschreiben', 'anschreiben',
  ];
  static const List<String> _softwareIntentWords = [
    'fehler', 'error', 'bug', 'installier', 'konfigur', 'setup',
    'tutorial', 'anleitung', 'how to', 'howto', 'api', 'sdk',
    'dokumentation', 'docs', 'library', 'framework',
  ];

  StammdatenContext resolve({
    required String what,
    required String why,
    required Map<String, dynamic> settings,
    double employmentWeight = 1.0,
  }) {
    final softTerms = <String>[];
    final hardTerms = <String>[];
    final preferredSources = <String>[];
    final excludeDomains = <String>[];
    final trustDomains = <String>[];
    final fileTypeHints = <String>[];

    final fullText = '${what.toLowerCase()} ${why.toLowerCase()}';
    final hasLocation  = _containsAny(fullText, _locationIntentWords);
    final hasJob       = _containsAny(fullText, _jobIntentWords);
    final hasJobSearch = _containsAny(fullText, _jobSearchIntentWords);
    final hasAcademic  = _containsAny(fullText, _academicIntentWords);
    final hasNews      = _containsAny(fullText, _newsIntentWords);
    final hasMedical   = _containsAny(fullText, _medicalIntentWords);
    final hasFinancial = _containsAny(fullText, _financialIntentWords);
    final hasCvIntent  = _containsAny(fullText, _cvIntentWords);
    final hasSoftware  = _containsAny(fullText, _softwareIntentWords);

    final employmentType =
        ((settings['employmentType'] as String?) ?? 'student').trim();
    final beruf   = ((settings['beruf']    as String?) ?? '').trim();
    final plz     = ((settings['plz']      as String?) ?? '').trim();
    final language= ((settings['language'] as String?) ?? 'de').trim();
    final country = ((settings['country']  as String?) ?? 'de').trim();
    final jahr    = (settings['jahr']      as int?)    ?? 1990;

    // ─────────────────────────────────────────────────────────────
    // 1. QUELLEN-PRESET (skaliert durch employmentWeight)
    // ─────────────────────────────────────────────────────────────
    final preset = _employmentSourcePresets[employmentType];
    if (preset != null && employmentWeight >= 0.7) {
      final count = employmentWeight >= 1.4
          ? preset.length
          : (employmentWeight >= 1.0 ? 2 : 1);
      preferredSources.addAll(preset.take(count));
    }

    // ─────────────────────────────────────────────────────────────
    // 2. STUDENT-SPEZIFISCH
    //    → Academic-Boost, PDF bei Fachfragen, Uni-Domains
    // ─────────────────────────────────────────────────────────────
    bool preferIntitle = false;
    String? dateAfter;

    if (employmentType == 'student') {
      // Akademische Fachfrage: PDF-Filter und Uni-Domain-Boost
      if (hasAcademic) {
        fileTypeHints.add('pdf');
        if (!preferredSources.contains('academic')) {
          preferredSources.insert(0, 'academic');
        }
        softTerms.add('Zusammenfassung');
      }
    }

    // ─────────────────────────────────────────────────────────────
    // 3. RENTNER-SPEZIFISCH
    //    → Schutzwall, Trust-Domains fuer Medizin/Finanzen
    // ─────────────────────────────────────────────────────────────
    if (employmentType == 'rentner') {
      excludeDomains.addAll(_rentnerExclusions);
      // Foren entfernen (Spec: Social-Media-Lärm und Scam-Risiko)
      preferredSources.removeWhere(
          (s) => s == 'foren' || s == 'reddit' || s == 'social');

      if (hasMedical) {
        trustDomains.addAll(_rentnerMedicalTrustDomains);
        if (!preferredSources.contains('offiziell')) {
          preferredSources.insert(0, 'offiziell');
        }
      }
      if (hasFinancial) {
        trustDomains.addAll(_rentnerFinancialTrustDomains);
      }
    }

    // ─────────────────────────────────────────────────────────────
    // 4. VOLLZEIT-SPEZIFISCH
    //    → intitle: fuer Top-Keyword, after: Aktualitaet,
    //      Gutefrage abstrafen
    // ─────────────────────────────────────────────────────────────
    if (employmentType == 'vollzeit') {
      excludeDomains.addAll(_vollzeitExclusions);
      // intitle: bei Software/Tool-Fragen (kein langes Lesen)
      if (hasSoftware || hasJob) {
        preferIntitle = true;
      }
      // Aktualitaets-Filter: immer fuer Vollzeit (niemand will 5 Jahre alte Tipps)
      final cutoffYear = DateTime.now().year - 1;
      dateAfter = '$cutoffYear-01-01';
    }

    // ─────────────────────────────────────────────────────────────
    // 5. TEILZEIT-SPEZIFISCH
    //    → Reddit/Community-Foren aufwerten, Content-Farmen abstrafen
    // ─────────────────────────────────────────────────────────────
    if (employmentType == 'teilzeit') {
      excludeDomains.addAll(_teilzeitExclusions);
      // Community-Foren und echte Erfahrungsberichte priorisieren
      if (!preferredSources.contains('reddit')) {
        preferredSources.insert(0, 'reddit');
      }
      // Lokal-Intent: PLZ in hardTerms
      if (hasLocation && plz.isNotEmpty && plz != '0') {
        hardTerms.add(plz);
        softTerms.add(country == 'de' ? 'Deutschland' : country.toUpperCase());
      }
    }

    // ─────────────────────────────────────────────────────────────
    // 6. ERWERBSLOS-SPEZIFISCH
    //    → Stellenboersen an die Spitze, CV-Vorlagen filetype:,
    //      Coaching-Scams ausschliessen
    // ─────────────────────────────────────────────────────────────
    if (employmentType == 'erwerbslos') {
      excludeDomains.addAll(_erwerbslosExclusions);

      if (hasJobSearch) {
        // Stellenboersen explizit nach vorne
        if (!preferredSources.contains('stellenboersen')) {
          preferredSources.insert(0, 'stellenboersen');
        }
      }
      // Lebenslauf-Vorlage: filetype:doc und filetype:pdf
      if (hasCvIntent) {
        fileTypeHints.addAll(['doc', 'pdf']);
        softTerms.add('Vorlage');
      }
    }

    // ─────────────────────────────────────────────────────────────
    // 7. GEMEINSAME INTENT-LOGIK
    // ─────────────────────────────────────────────────────────────

    // Job-Intent: Beruf + Vollzeit/Teilzeit-Marker
    if (hasJob) {
      if (beruf.isNotEmpty) {
        hardTerms.add(beruf.contains(' ') ? '"$beruf"' : beruf);
      }
      if (employmentType == 'vollzeit' || employmentType == 'teilzeit') {
        softTerms.add(employmentType);
      }
    } else if (beruf.isNotEmpty) {
      softTerms.add(beruf.toLowerCase().split(' ').first);
    }

    // Lokal-Intent (allgemein, nicht nur Teilzeit)
    if (hasLocation && plz.isNotEmpty && plz != '0' &&
        !hardTerms.contains(plz)) {
      hardTerms.add(plz);
    }

    // Academic-Intent allgemein
    if (hasAcademic && employmentType != 'student') {
      if (!preferredSources.contains('academic')) {
        preferredSources.insert(0, 'academic');
      }
    }

    // News-Intent: News-Quellen vorne
    if (hasNews) {
      if (!preferredSources.contains('news')) {
        preferredSources.insert(0, 'news');
      }
    }

    // ─────────────────────────────────────────────────────────────
    // 8. SPRACHE + AKTUALITAET
    // ─────────────────────────────────────────────────────────────
    final languageHint = (language == 'de' || language == 'en')
        ? 'lang_$language'
        : null;

    final age = DateTime.now().year - jahr;
    final boostRecent = hasNews || (age >= 0 && age <= 30) ||
        employmentType == 'vollzeit';

    // ─────────────────────────────────────────────────────────────
    // 9. DEDUPLIZIEREN + ZUSAMMENFUEHREN
    // ─────────────────────────────────────────────────────────────
    final seen = <String>{};
    final orderedSources = <String>[];
    for (final s in preferredSources) {
      if (seen.add(s)) orderedSources.add(s);
    }

    final seenTrust = <String>{};
    final orderedTrust = <String>[];
    for (final d in trustDomains) {
      if (seenTrust.add(d)) orderedTrust.add(d);
    }

    return StammdatenContext(
      softTerms: softTerms,
      hardTerms: hardTerms,
      preferredSources: orderedSources,
      excludeDomains: List.unmodifiable(excludeDomains.toSet().toList()),
      trustDomains: orderedTrust,
      fileTypeHints: List.unmodifiable(fileTypeHints.toSet().toList()),
      languageHint: languageHint,
      dateAfter: dateAfter,
      boostRecent: boostRecent,
      preferIntitle: preferIntitle,
    );
  }

  bool _containsAny(String haystack, List<String> needles) {
    for (final n in needles) {
      if (haystack.contains(n)) return true;
    }
    return false;
  }
}
