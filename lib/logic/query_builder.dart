import 'package:shared_preferences/shared_preferences.dart';
import '../utils/findux_stopwords.dart';
import '../coach/coach_models.dart';
import '../coach/phrase_detector.dart';
import '../coach/smart_date.dart';
import 'stammdaten_resolver.dart';

/// FindUX Query-Builder (v3, Coach-aware).
///
/// Pipeline:
///   1) WAS  -> Phrase oder Token-Set, Mode-abhaengig formatiert
///              + Phrase-Auto-Detect (Multi-Wort-Wendungen automatisch quoten)
///   2) WARUM -> Kontext-Tokens, dedupliziert ggn. WAS, Stoppwoerter raus
///   3) Stammdaten-Resolver liefert harte/weiche Terme + Source-Bias
///   4) Coach-Injection (HardTerms, Phrases, Intitles, Sites, Excludes, after)
///   5) Lern-Boost (positive Keywords als OR-Erweiterung)
///   6) Lern-Demote (negative Keywords + Domains)
///   7) site:(...)-Gruppe + filetype:(...)-Gruppe (jeweils EINE)
///   8) Smart-Date: after:DATE wenn Intent es nahelegt (kein Coach-after gesetzt)
///   9) Spam-Filter + Jugendschutz
///
/// Strikte Regeln:
///   - max 1 site:(...)-Gruppe, max 1 filetype:(...)-Gruppe
///   - max 8 Domains in der site-Gruppe (Google bricht sonst silent ab)
///   - keine Zeichen-Inflation: Query <= 1800 Zeichen vor URL-Encoding
///   - keine Operatoren in der Query verdoppeln
class FindUXQueryBuilder {
  final StammdatenResolver _stammdaten = StammdatenResolver();

  // ==================== Quellen / Dateien ====================

  static const Map<String, List<String>> sourceDomains = {
    'foren': [
      'reddit.com', 'stackoverflow.com', 'stackexchange.com',
      'gutefrage.net',
    ],
    'reddit': ['reddit.com'],
    'news': [
      'spiegel.de', 'zeit.de', 'sueddeutsche.de', 'faz.net', 'taz.de',
      'tagesschau.de', 'heise.de', 'golem.de', 'bbc.com', 'reuters.com',
    ],
    'wikipedia': ['wikipedia.org', 'wikimedia.org'],
    'offiziell': [
      'gov', 'edu', 'europa.eu', 'bund.de', 'admin.ch', 'gv.at',
    ],
    'academic': [
      'edu', 'ac.uk', 'researchgate.net', 'arxiv.org', 'jstor.org',
      'springer.com', 'sciencedirect.com', 'semanticscholar.org',
      'scholar.google.com',
    ],
    'video': ['youtube.com', 'vimeo.com', 'dailymotion.com'],
    'blogs': ['medium.com', 'substack.com', 'wordpress.com', 'blogspot.com'],
    'shops': [
      'amazon.de', 'ebay.de', 'otto.de', 'idealo.de', 'geizhals.de',
      'mediamarkt.de', 'saturn.de',
    ],
    'social': [
      'twitter.com', 'x.com', 'facebook.com', 'linkedin.com',
      'mastodon.social', 'bsky.app',
    ],
    'code': ['github.com', 'gitlab.com', 'bitbucket.org', 'codeberg.org'],
    'docs': [
      'developer.mozilla.org', 'docs.python.org', 'docs.microsoft.com',
      'developer.apple.com', 'docs.flutter.dev',
    ],
    'stellenboersen': [
      'stepstone.de', 'indeed.com', 'monster.de', 'arbeitsagentur.de',
      'xing.com', 'linkedin.com', 'jobware.de', 'stellenanzeigen.de',
    ],
  };

  static const Map<String, List<String>> fileExtensions = {
    'pdf': ['pdf'],
    'ppt': ['pptx', 'ppt', 'key', 'odp'],
    'doc': ['docx', 'doc', 'odt', 'rtf'],
    'xls': ['xlsx', 'xls', 'csv', 'ods'],
    'images': ['jpg', 'jpeg', 'png', 'webp'],
    'audio': ['mp3', 'wav', 'flac', 'ogg'],
    'video_file': ['mp4', 'mkv', 'webm'],
    'archive': ['zip', 'tar', 'gz', '7z'],
    'ebook': ['epub', 'mobi'],
  };

  static const List<String> noiseExclusions = [
    '-inurl:utm_',
    '-inurl:promo',
    '-inurl:sponsored',
    '-intitle:sponsored',
    '-intitle:advertorial',
  ];

  static const List<String> defaultBlockedDomains = [
    '-site:pinterest.com',
    '-site:pinterest.de',
    '-site:answers.yahoo.com',
    '-site:tripadvisor.com',
    '-site:w3schools.com',
  ];

  static const List<String> explicitExclusions = [
    '-sex', '-porn', '-nude', '-gambling', '-betting', '-erotik', '-xxx',
  ];

  // ==================== Public API ====================

  Future<String> buildQuery({
    required String what,
    required String why,
    required List<String> filters,
    required Map<String, dynamic> settings,
    String mode = 'standard',
    CoachInjection? coachInjection,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final weights = _loadWeights(prefs);
    final language = (settings['language'] as String?) ?? 'de';
    final stopwords = stopwordsForLanguage(language);

    final employmentType = (settings['employmentType'] as String?) ?? 'student';
    final employmentWeight = weights['weight_employment_$employmentType'] ?? 1.0;

    final stamm = _stammdaten.resolve(
      what: what,
      why: why,
      settings: settings,
      employmentWeight: employmentWeight,
    );

    final parts = <String>[];
    final usedTokens = <String>{};

    // 1. WAS: Mode-abhaengige Formatierung + Auto-Quote-Phrase
    final cleanWhatRaw = _normalizeQuotes(what).trim();
    // Auto-Quote nur wenn nicht discover und User hat noch keine Quotes
    final cleanWhat = (mode != 'discover' && !cleanWhatRaw.contains('"'))
        ? PhraseDetector.autoQuote(cleanWhatRaw)
        : cleanWhatRaw;
    if (cleanWhat.isNotEmpty) {
      parts.add(_formatPrimary(cleanWhat, mode));
      usedTokens.addAll(_lowercaseTokens(cleanWhat));
    }

    // 2. Top-Keyword als intitle: im precise-Mode ODER bei stamm.preferIntitle (Vollzeit)
    if (mode == 'precise' || stamm.preferIntitle) {
      final topKw = _extractTopKeyword(cleanWhat, stopwords);
      if (topKw != null && topKw.length >= 4) {
        parts.add('intitle:$topKw');
      }
    }

    // 3. WARUM-Kontext (deduped, ohne Stoppwoerter)
    final contextKeywords = _tokenize(why, stopwords)
        .where((t) => !usedTokens.contains(t.toLowerCase()))
        .toList();
    if (contextKeywords.isNotEmpty) {
      if (mode == 'discover' && contextKeywords.length >= 2) {
        parts.add('(${contextKeywords.take(4).join(' OR ')})');
      } else {
        parts.add(contextKeywords.take(4).join(' '));
      }
      usedTokens.addAll(contextKeywords.map((e) => e.toLowerCase()));
    }

    // 4. Stammdaten-Hard-Terms
    for (final t in stamm.hardTerms) {
      final lower = t.replaceAll('"', '').toLowerCase();
      if (!usedTokens.contains(lower)) {
        parts.add(t);
        usedTokens.add(lower);
      }
    }

    // 5. Stammdaten-Soft-Terms (nur in standard/discover)
    if (mode != 'precise' && stamm.softTerms.isNotEmpty) {
      final softs = stamm.softTerms
          .where((t) => !usedTokens.contains(t.toLowerCase()))
          .take(2)
          .toList();
      if (softs.length >= 2) {
        parts.add('(${softs.join(' OR ')})');
      } else if (softs.length == 1) {
        parts.add(softs.first);
      }
      usedTokens.addAll(softs.map((e) => e.toLowerCase()));
    }

    // 6. Coach-Injection (HardTerms, Phrases, Intitles, Excludes — Sites kommen spaeter)
    final coachSites = <String>[];
    String? coachAfter;
    if (coachInjection != null && !coachInjection.isEmpty) {
      for (final t in coachInjection.hardTerms) {
        final lower = t.toLowerCase();
        if (!usedTokens.contains(lower)) {
          parts.add(t);
          usedTokens.add(lower);
        }
      }
      for (final p in coachInjection.phrases) {
        final phr = p.replaceAll('"', '').trim();
        if (phr.isEmpty) continue;
        parts.add('"$phr"');
      }
      for (final t in coachInjection.intitles) {
        final clean = t.toLowerCase().trim();
        if (clean.isEmpty) continue;
        parts.add('intitle:$clean');
      }
      coachSites.addAll(coachInjection.sites);
      for (final e in coachInjection.excludes) {
        final clean = e.replaceAll(RegExp(r'^-+'), '').trim();
        if (clean.isEmpty) continue;
        parts.add('-$clean');
      }
      coachAfter = coachInjection.after;
    }

    // 7. Lern-Boost: Top-3 positive Keywords als OR-Gruppe
    final boostKws = _topLearnedKeywords(weights, positive: true, max: 3)
        .where((k) => !usedTokens.contains(k))
        .toList();
    if (boostKws.isNotEmpty && mode != 'precise') {
      if (boostKws.length == 1) {
        parts.add(boostKws.first);
      } else {
        parts.add('(${boostKws.join(' OR ')})');
      }
    }

    // 8. Lern-Demote: Top-3 negative Keywords als -term
    final demoteKws = _topLearnedKeywords(weights, positive: false, max: 3);
    for (final kw in demoteKws) {
      parts.add('-$kw');
    }

    // 9. Quellen-Bias: User + Stammdaten + Coach-Sites in EINE site-Gruppe
    final effectiveFilters = _resolveEffectiveFilters(filters, stamm);
    final sortedFilters = _sortFiltersByWeight(effectiveFilters, weights);
    final filterSiteDomains = _collectSiteDomains(sortedFilters);
    // TrustDomains (Rentner: stiftung-warentest etc.) haben Vorrang im site:-Block
    final mergedSites = <String>{...stamm.trustDomains, ...filterSiteDomains, ...coachSites};
    final siteGroup = _buildSiteGroupFromDomains(mergedSites);
    if (siteGroup != null) parts.add(siteGroup);
    // Stammdaten-FileTypeHints als Fallback wenn kein User-Filetype gesetzt
    final fileGroup = _buildFiletypeGroup(sortedFilters) ??
        (stamm.fileTypeHints.isNotEmpty
            ? _buildFiletypeGroupFromList(stamm.fileTypeHints)
            : null);
    if (fileGroup != null) parts.add(fileGroup);

    // 10. Lern-Domain-Demote
    final badDomains = _topLearnedDomains(weights, positive: false, max: 3);
    for (final d in badDomains) {
      parts.add('-site:$d');
    }
    // Beschaeftigungstyp-spezifische Ausschluesse (Pinterest fuer Rentner, gutefrage fuer Vollzeit)
    for (final d in stamm.excludeDomains) {
      parts.add('-site:$d');
    }

    // 11. Datum: Coach-after > recent-Mode > Stammdaten-boostRecent > Smart-Date-Heuristik
    if (coachAfter != null && coachAfter.isNotEmpty) {
      parts.add('after:$coachAfter');
    } else if (stamm.dateAfter != null && stamm.dateAfter!.isNotEmpty) {
      // Beschaeftigungstyp-spezifisch (z.B. Vollzeit: after:2024-01-01)
      parts.add('after:${stamm.dateAfter}');
    } else if (mode == 'recent' ||
        (stamm.boostRecent && mode == 'standard')) {
      final cutoff = DateTime.now().subtract(const Duration(days: 365));
      parts.add('after:${_isoDate(cutoff)}');
    } else if (mode != 'precise') {
      final smartAfter = SmartDate.formatAfterOperator(what, why);
      if (smartAfter != null) parts.add(smartAfter);
    }

    // 12. Standard-Filter
    parts.addAll(noiseExclusions);
    parts.addAll(defaultBlockedDomains);

    // 13. Jugendschutz
    final isYouthActive =
        (settings['enableYouthProtection'] as bool?) ?? true;
    if (isYouthActive) parts.addAll(explicitExclusions);

    // 14. Build + sanitize
    return _sanitize(parts);
  }

  String buildSearchUrl(
      String query, String engine, Map<String, dynamic> settings) {
    String base;
    final params = StringBuffer();
    final isYouthActive =
        (settings['enableYouthProtection'] as bool?) ?? true;
    final lang = (settings['language'] as String?) ?? 'de';
    final country = (settings['country'] as String?) ?? 'de';

    switch (engine) {
      case 'bing':
        base = 'https://www.bing.com/search?q=';
        params.write('&setlang=$lang&cc=${country.toUpperCase()}');
        if (isYouthActive) params.write('&safeSearch=Strict');
        break;
      case 'duckduckgo':
        base = 'https://duckduckgo.com/?q=';
        params.write('&kl=$country-$lang');
        if (isYouthActive) params.write('&kp=1');
        break;
      case 'startpage':
        base = 'https://www.startpage.com/do/search?q=';
        params.write('&language=${_langName(lang)}');
        break;
      case 'brave':
        base = 'https://search.brave.com/search?q=';
        params.write('&country=${country.toUpperCase()}');
        if (isYouthActive) params.write('&safesearch=strict');
        break;
      default: // google
        base = 'https://www.google.com/search?q=';
        params.write('&hl=$lang&gl=${country.toUpperCase()}');
        params.write('&lr=lang_$lang');
        params.write('&filter=1');
        params.write('&num=20');
        if (isYouthActive) params.write('&safe=active');
        // Stage 14/15: Doppelt gegen "Meinten Sie ..."-Banner und
        // Synonym-Expansion absichern.
        //
        //   nfpr=1   = "no fix prediction" — Rechtschreib-Korrektur AUS.
        //              Reicht aber NICHT bei komplexen Queries mit OR /
        //              Ausschluss-Operatoren — Google wirft dann doch noch
        //              Korrektur-/Synonym-Vorschlaege ein.
        //
        //   tbs=li:1 = "literal: 1" — Verbatim-Modus, dasselbe wie wenn
        //              der User in Google "Tools -> Alle Ergebnisse ->
        //              Woertlich" anklickt. Erzwingt EXAKT die Tokens der
        //              Query, deaktiviert Synonyme, deaktiviert "Meinten
        //              Sie ...", deaktiviert weiche Treffer.
        //
        // Die Kombination ist robust auch gegen die komplexen Queries
        // mit Quotes, OR-Gruppen und mehreren -site:/-inurl:-Filtern,
        // die der Query-Builder produziert.
        params.write('&nfpr=1');
        params.write('&tbs=li:1');
    }

    if (query.length > 1800) query = query.substring(0, 1790).trim();
    return base + Uri.encodeComponent(query) + params.toString();
  }

  // ==================== Helpers ====================

  Map<String, double> _loadWeights(SharedPreferences prefs) {
    final w = <String, double>{};
    for (final key in prefs.getKeys()) {
      if (key.startsWith('weight_')) {
        w[key] = prefs.getDouble(key) ?? 1.0;
      }
    }
    return w;
  }

  String _normalizeQuotes(String s) =>
      s.replaceAll(RegExp(r'[“”„‟]'), '"').replaceAll(RegExp(r'\s+'), ' ');

  String _formatPrimary(String what, String mode) {
    final hasSpace = what.contains(' ');
    final alreadyQuoted = what.contains('"');
    if (alreadyQuoted) return what;
    switch (mode) {
      case 'discover':
        return what;
      case 'precise':
      default:
        return hasSpace ? '"$what"' : what;
    }
  }

  Set<String> _lowercaseTokens(String s) => s
      .replaceAll('"', '')
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toSet();

  String? _extractTopKeyword(String what, Set<String> stopwords) {
    if (what.isEmpty) return null;
    final tokens = what
        .replaceAll('"', '')
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.length >= 4 && !stopwords.contains(t))
        .toList();
    return tokens.isEmpty ? null : tokens.first;
  }

  List<String> _tokenize(String s, Set<String> stopwords) {
    if (s.isEmpty) return const [];
    return s
        .split(RegExp(r'[,;\s]+'))
        .map((t) => t.trim())
        .where((t) => t.length > 2 && !stopwords.contains(t.toLowerCase()))
        .toList();
  }

  List<String> _topLearnedKeywords(Map<String, double> weights,
      {required bool positive, required int max}) {
    final entries = <MapEntry<String, double>>[];
    weights.forEach((key, weight) {
      if (!key.startsWith('weight_kw_')) return;
      if (positive ? weight > 1.4 : weight < 0.7) {
        entries.add(MapEntry(key.replaceFirst('weight_kw_', ''), weight));
      }
    });
    entries.sort((a, b) =>
        positive ? b.value.compareTo(a.value) : a.value.compareTo(b.value));
    return entries.take(max).map((e) => e.key).toList();
  }

  List<String> _topLearnedDomains(Map<String, double> weights,
      {required bool positive, required int max}) {
    final entries = <MapEntry<String, double>>[];
    weights.forEach((key, weight) {
      if (!key.startsWith('weight_domain_')) return;
      if (positive ? weight > 1.5 : weight < 0.6) {
        entries.add(MapEntry(key.replaceFirst('weight_domain_', ''), weight));
      }
    });
    entries.sort((a, b) =>
        positive ? b.value.compareTo(a.value) : a.value.compareTo(b.value));
    return entries.take(max).map((e) => e.key).toList();
  }

  List<String> _resolveEffectiveFilters(
      List<String> userFilters, StammdatenContext stamm) {
    final hasExplicit =
        userFilters.where((f) => f != 'alle').isNotEmpty;
    if (hasExplicit) return userFilters.where((f) => f != 'alle').toList();
    // KEIN Stammdaten-Fallback mehr: wenn der User "alle" gewaehlt hat,
    // wird auch wirklich alles durchsucht — keine versteckte site:-Whitelist.
    // Das verhindert dass z.B. "Rezepte" an reddit/stackoverflow gebunden wird.
    return const [];
  }

  List<String> _sortFiltersByWeight(
      List<String> filters, Map<String, double> weights) {
    final list = filters.toList();
    list.sort((a, b) {
      final wa = weights['weight_filter_$a'] ?? 1.0;
      final wb = weights['weight_filter_$b'] ?? 1.0;
      return wb.compareTo(wa);
    });
    return list
        .where((f) => (weights['weight_filter_$f'] ?? 1.0) >= 0.7)
        .toList();
  }

  Set<String> _collectSiteDomains(List<String> filters) {
    final domains = <String>{};
    for (final f in filters) {
      final ds = sourceDomains[f];
      if (ds != null) domains.addAll(ds);
    }
    return domains;
  }

  String? _buildSiteGroupFromDomains(Set<String> domains) {
    if (domains.isEmpty) return null;
    if (domains.length == 1) return 'site:${domains.first}';
    final parts = domains.take(8).map((d) => 'site:$d').toList();
    return '(${parts.join(' OR ')})';
  }

  /// Baut filetype:(...)-Gruppe aus Stammdaten-Hints (wenn kein User-Filter gesetzt).
  String? _buildFiletypeGroupFromList(List<String> hints) {
    if (hints.isEmpty) return null;
    final parts = hints.map((h) => 'filetype:' + h).toList();
    if (parts.length == 1) return parts.first;
    return '(' + parts.join(' OR ') + ')';
  }

  String? _buildFiletypeGroup(List<String> filters) {
    final exts = <String>{};
    for (final f in filters) {
      final es = fileExtensions[f];
      if (es != null) exts.addAll(es);
    }
    if (exts.isEmpty) return null;
    if (exts.length == 1) return 'filetype:${exts.first}';
    final parts = exts.take(6).map((e) => 'filetype:$e').toList();
    return '(${parts.join(' OR ')})';
  }

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _langName(String code) {
    switch (code) {
      case 'de': return 'deutsch';
      case 'en': return 'english';
      case 'fr': return 'francais';
      case 'es': return 'espanol';
      case 'it': return 'italiano';
      default: return 'english';
    }
  }

  String _sanitize(List<String> parts) {
    final out = parts.where((p) => p.isNotEmpty).toList();
    final seen = <String>{};
    final unique = <String>[];
    for (final p in out) {
      if (seen.add(p)) unique.add(p);
    }
    return unique.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
