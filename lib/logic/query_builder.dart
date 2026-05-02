import 'package:shared_preferences/shared_preferences.dart';

/// Query-Builder fuer FindUX. Nutzt soviel von Googles Suchoperatoren wie
/// sinnvoll, OHNE die Query mit redundanten Operatoren zu ueberladen
/// (Google faellt bei zu viel Logik auf Naive-Matching zurueck).
///
/// Kern-Strategie:
///   - "WAS" -> exakte Phrase ODER lockerer Match je nach Mode
///   - "WARUM" -> Kontext-Begriffe (intitle: fuer das wichtigste)
///   - Filter -> EINE site:(...)-Gruppe + EINE filetype:(...)-Gruppe
///   - Lern-Boost: Top-3 positive Keywords als OR-Erweiterung
///   - Lern-Exclude: Top-3 negative Keywords als -term
///   - Mode-Strategie:
///       precise   -> "phrase" + intitle:topkw  (Praezision)
///       standard  -> Phrase + Kontext (Balance)
///       discover  -> lose OR-Expansion        (Recall)
///       recent    -> after:DATE (letzte 12 Mon.)
///   - Default-Negativ-Filter: AI-Slop / Content-Farms / Ads / Tracker-Pfade
class FindUXQueryBuilder {
  // ------- KONSTANTEN -------

  /// Mehrere Domains pro Quelle: bevorzugte (qualitativ hochwertige) Sites
  /// in einer EINZIGEN site:(...)-OR-Gruppe.
  final Map<String, List<String>> sourceDomains = const {
    'foren': [
      'reddit.com',
      'stackoverflow.com',
      'stackexchange.com',
      'quora.com',
      'gutefrage.net',
    ],
    'reddit': ['reddit.com'],
    'news': [
      'spiegel.de',
      'zeit.de',
      'sueddeutsche.de',
      'faz.net',
      'taz.de',
      'tagesschau.de',
      'heise.de',
      'golem.de',
      'bbc.com',
      'reuters.com',
    ],
    'wikipedia': ['wikipedia.org', 'wikimedia.org'],
    'offiziell': [
      // .gov / .edu / .mil als Pseudo-Domains via site:
      'gov',
      'edu',
      'europa.eu',
      'bund.de',
      'admin.ch',
      'gv.at',
    ],
    'academic': [
      'edu',
      'ac.uk',
      'researchgate.net',
      'arxiv.org',
      'jstor.org',
      'springer.com',
      'sciencedirect.com',
      'semanticscholar.org',
    ],
    'video': ['youtube.com', 'vimeo.com', 'dailymotion.com'],
    'blogs': ['medium.com', 'substack.com', 'wordpress.com', 'blogspot.com'],
    'shops': [
      'amazon.de',
      'ebay.de',
      'otto.de',
      'idealo.de',
      'geizhals.de',
      'mediamarkt.de',
      'saturn.de',
    ],
    'social': [
      'twitter.com',
      'x.com',
      'facebook.com',
      'linkedin.com',
      'mastodon.social',
      'bsky.app',
    ],
    'code': ['github.com', 'gitlab.com', 'bitbucket.org', 'codeberg.org'],
    'docs': [
      'developer.mozilla.org',
      'docs.python.org',
      'docs.microsoft.com',
      'developer.apple.com',
      'docs.flutter.dev',
    ],
  };

  /// Datei-Operatoren: jeweils alle relevanten Endungen in einer Gruppe.
  final Map<String, List<String>> fileExtensions = const {
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

  /// Allgemeine Spam- und Low-Quality-Pfade, die wir IMMER ausschliessen.
  /// In einer eigenen Gruppe, damit der User-Context nicht ueberlagert wird.
  static const List<String> noiseExclusions = [
    '-inurl:ads',
    '-inurl:promo',
    '-inurl:sponsored',
    '-inurl:utm_',
    '-intitle:sponsored',
    '-intitle:advertorial',
  ];

  /// Bekannt schlechte Domains, die fast nie gute Resultate bringen
  /// (Content-Farms, AI-Slop, Pinterest-SEO, Comparison-Spam).
  static const List<String> defaultBlockedDomains = [
    '-site:pinterest.com',
    '-site:pinterest.de',
    '-site:quora.com',
    '-site:answers.yahoo.com',
    '-site:tripadvisor.com',
    '-site:w3schools.com', // bevorzuge MDN
  ];

  static const List<String> explicitExclusions = [
    '-sex',
    '-porn',
    '-nude',
    '-gambling',
    '-betting',
    '-erotik',
    '-xxx',
  ];

  // ------- API -------

  Future<String> buildQuery({
    required String what,
    required String why,
    required List<String> filters,
    required Map<String, dynamic> settings,
    String mode = 'standard',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final weights = _loadWeights(prefs);

    final parts = <String>[];

    // 1. WAS: Phrase oder Begriff(e)
    final cleanWhat = _normalizeQuotes(what).trim();
    if (cleanWhat.isNotEmpty) {
      parts.add(_formatPrimary(cleanWhat, mode));
    }

    // 2. Top-Keyword als intitle: (nur wenn ein klarer Hauptbegriff existiert)
    final topKw = _extractTopKeyword(cleanWhat);
    if (mode == 'precise' && topKw != null && topKw.length >= 4) {
      parts.add('intitle:$topKw');
    }

    // 3. WARUM -> Kontext-Begriffe (lockerer Match, keine Operatoren)
    final contextKeywords = _tokenize(why);
    if (contextKeywords.isNotEmpty) {
      // discover-Mode: OR-Verkettung fuer mehr Recall
      if (mode == 'discover' && contextKeywords.length >= 2) {
        parts.add('(${contextKeywords.take(4).join(' OR ')})');
      } else {
        parts.add(contextKeywords.take(4).join(' '));
      }
    }

    // 4. Persoenliche Signale (Beruf / PLZ als reine Begriffe)
    final beruf = (settings['beruf'] as String?)?.trim() ?? '';
    if (beruf.isNotEmpty && mode != 'discover') {
      parts.add(beruf.contains(' ') ? '"$beruf"' : beruf);
    }
    final plz = (settings['plz'] as String?)?.trim() ?? '';
    if (plz.isNotEmpty && plz != '0') {
      parts.add(plz);
    }

    // 5. Lern-Boost: Top-N positive Keywords als OR-Gruppe
    final boostKws = _topLearnedKeywords(weights, positive: true, max: 3);
    if (boostKws.isNotEmpty && mode != 'precise') {
      parts.add('(${boostKws.join(' OR ')})');
    }

    // 6. Lern-Exclude: Top-N stark negative Keywords als -term
    final demoteKws = _topLearnedKeywords(weights, positive: false, max: 3);
    for (final kw in demoteKws) {
      parts.add('-$kw');
    }

    // 7. Filter -> EINE site:(...) und EINE filetype:(...) Gruppe
    final sortedFilters = _sortFiltersByWeight(filters, weights);
    final siteGroup = _buildSiteGroup(sortedFilters, weights);
    if (siteGroup != null) parts.add(siteGroup);
    final fileGroup = _buildFiletypeGroup(sortedFilters, weights);
    if (fileGroup != null) parts.add(fileGroup);

    // 8. Mode-spezifische Datums-Eingrenzung
    if (mode == 'recent') {
      final cutoff = DateTime.now().subtract(const Duration(days: 365));
      parts.add('after:${_isoDate(cutoff)}');
    }

    // 9. Standard-Negativ-Filter (Spam / Ads)
    parts.addAll(noiseExclusions);
    parts.addAll(defaultBlockedDomains);

    // 10. Jugendschutz
    final isYouthActive = (settings['enableYouthProtection'] as bool?) ?? true;
    if (isYouthActive) parts.addAll(explicitExclusions);

    // 11. Zusammenbau + Whitespace-Sanitize
    return parts
        .where((p) => p.isNotEmpty)
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String buildSearchUrl(
      String query, String engine, Map<String, dynamic> settings) {
    String base;
    final params = StringBuffer();
    final isYouthActive = (settings['enableYouthProtection'] as bool?) ?? true;
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
      default:
        // Google
        base = 'https://www.google.com/search?q=';
        params.write('&hl=$lang&gl=${country.toUpperCase()}');
        params.write('&filter=1'); // Duplikate dedupliziert
        params.write('&num=20'); // 20 statt 10 Ergebnisse
        if (isYouthActive) params.write('&safe=active');
    }

    // Google's Limit: 2048 Zeichen URL-gesamt. Kuerze Query auf 1800,
    // damit nach URL-Encoding noch Platz fuer Params bleibt.
    if (query.length > 1800) query = query.substring(0, 1790).trim();
    return base + Uri.encodeComponent(query) + params.toString();
  }

  // ------- HELPERS -------

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

  /// Format-Strategie fuer den Hauptbegriff je nach Mode.
  String _formatPrimary(String what, String mode) {
    final hasSpace = what.contains(' ');
    final alreadyQuoted = what.contains('"');
    if (alreadyQuoted) return what;
    switch (mode) {
      case 'precise':
        return hasSpace ? '"$what"' : what;
      case 'discover':
        // bewusst KEINE Quotes -> Google darf erweitern
        return what;
      default:
        return hasSpace ? '"$what"' : what;
    }
  }

  /// Erstes "starkes" Wort (>=4 Zeichen, kein Stoppwort) als intitle:-Kandidat.
  String? _extractTopKeyword(String what) {
    if (what.isEmpty) return null;
    final tokens = what
        .replaceAll('"', '')
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.length >= 4 && !_germanStopwords.contains(t))
        .toList();
    return tokens.isEmpty ? null : tokens.first;
  }

  List<String> _tokenize(String s) {
    if (s.isEmpty) return const [];
    return s
        .split(RegExp(r'[,;\s]+'))
        .map((t) => t.trim())
        .where((t) => t.length > 2 && !_germanStopwords.contains(t.toLowerCase()))
        .toList();
  }

  /// Liefert Top-N Keywords aus den gelernten Gewichten.
  /// positive=true -> stark gewichtete (weight > 1.5)
  /// positive=false -> stark abgewertete (weight < 0.7)
  List<String> _topLearnedKeywords(
      Map<String, double> weights, {required bool positive, required int max}) {
    final entries = <MapEntry<String, double>>[];
    weights.forEach((key, weight) {
      if (!key.startsWith('weight_kw_')) return;
      if (positive ? weight > 1.5 : weight < 0.7) {
        entries.add(MapEntry(key.replaceFirst('weight_kw_', ''), weight));
      }
    });
    entries.sort((a, b) =>
        positive ? b.value.compareTo(a.value) : a.value.compareTo(b.value));
    return entries.take(max).map((e) => e.key).toList();
  }

  List<String> _sortFiltersByWeight(
      List<String> filters, Map<String, double> weights) {
    final list = filters.toList();
    list.sort((a, b) {
      final wa = weights['weight_filter_$a'] ?? 1.0;
      final wb = weights['weight_filter_$b'] ?? 1.0;
      return wb.compareTo(wa);
    });
    // Nur Filter mit positiver Gewichtung beruecksichtigen
    return list.where((f) => (weights['weight_filter_$f'] ?? 1.0) >= 0.7).toList();
  }

  /// Baut max EINE site:(...) Gruppe aus allen aktiven Quellen-Filtern.
  String? _buildSiteGroup(List<String> filters, Map<String, double> weights) {
    final domains = <String>{};
    for (final f in filters) {
      final ds = sourceDomains[f];
      if (ds != null) domains.addAll(ds);
    }
    if (domains.isEmpty) return null;
    if (domains.length == 1) return 'site:${domains.first}';
    final parts = domains.take(8).map((d) => 'site:$d').toList();
    return '(${parts.join(' OR ')})';
  }

  /// Baut max EINE filetype:(...) Gruppe aus allen aktiven Datei-Filtern.
  String? _buildFiletypeGroup(
      List<String> filters, Map<String, double> weights) {
    final exts = <String>{};
    for (final f in filters) {
      final es = fileExtensions[f];
      if (es != null) exts.addAll(es);
    }
    // Spezialfall 'code' = Domain-basiert, kein filetype
    if (filters.contains('code')) {
      // Domain wird in _buildSiteGroup behandelt, aber 'code' ist nur in
      // sourceDomains, nicht in fileExtensions -> nichts zu tun
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
      case 'de':
        return 'deutsch';
      case 'en':
        return 'english';
      case 'fr':
        return 'francais';
      case 'es':
        return 'espanol';
      case 'it':
        return 'italiano';
      default:
        return 'english';
    }
  }

  // Kompakte Liste deutscher + englischer Stoppwoerter.
  static const Set<String> _germanStopwords = {
    'der','die','das','und','oder','aber','mit','von','zu','zum','zur','auf',
    'fuer','für','ist','bin','sind','war','waren','wird','werden','wurde',
    'haben','hat','hatte','sich','dass','weil','wenn','dann','also','noch',
    'nur','auch','als','wie','was','wer','wo','wann','warum','welche','dieser',
    'diese','dieses','jener','jene','jenes','sein','seine','ihr','ihre','mein',
    'meine','dein','deine','ein','eine','einen','einem','einer','eines','den',
    'dem','des','sie','ihm','ihn','ihnen','wir','uns','unser','unsere','euch',
    'euer','eure','ihnen','than','then','this','that','these','those','with',
    'from','your','have','will','would','could','should','about','what','when',
    'where','which','while','their','they','them','were','been','into','than',
  };
}
