import 'package:shared_preferences/shared_preferences.dart';

class FindUXQueryBuilder {
  // Mapping interner Filter auf Googles native 'Advanced Search' Operatoren
  final Map<String, String> sourceOperators = {
    'foren':
        ' (site:reddit.com OR site:stackoverflow.com OR inurl:forum OR inurl:community)',
    'reddit': ' site:reddit.com',
    'news':
        ' (site:spiegel.de OR site:zeit.de OR site:heise.de OR site:bbc.com)',
    'wikipedia': ' site:wikipedia.org',
    'offiziell': ' (site:.gov OR site:.edu OR site:.org)',
    'academic': ' (site:.edu OR site:.ac.uk OR inurl:scholar)',
    'video': ' (site:youtube.com OR site:vimeo.com)',
    'blogs': ' (inurl:blog OR site:medium.com)',
    'shops': ' (site:amazon.de OR site:ebay.de OR site:otto.de)',
    'social':
        ' (site:twitter.com OR site:facebook.com OR site:linkedin.com)',
  };

  final Map<String, String> fileOperators = {
    'pdf': ' filetype:pdf',
    'ppt': ' (filetype:pptx OR filetype:ppt)',
    'doc': ' (filetype:docx OR filetype:doc)',
    'xls': ' (filetype:xlsx OR filetype:xls)',
    'code': ' (site:github.com OR site:gitlab.com)',
    'images': ' (filetype:jpg OR filetype:png)',
  };

  static const List<String> noiseExclusions = [
    '-inurl:ads',
    '-inurl:promo',
    '-intitle:sponsored'
  ];
  static const List<String> explicitExclusions = [
    '-sex',
    '-porn',
    '-nude',
    '-gambling',
    '-betting'
  ];

  double _getLearnedWeight(String key, Map<String, double> weights) {
    return weights['weight_$key'] ?? 1.0;
  }

  Future<String> buildQuery({
    required String what,
    required String why,
    required List<String> filters,
    required Map<String, dynamic> settings,
    String mode = 'standard',
  }) async {
    String googleDork = '';
    final prefs = await SharedPreferences.getInstance();

    final Map<String, double> weights = {};
    for (final key in prefs.getKeys()) {
      if (key.startsWith('weight_')) {
        weights[key] = prefs.getDouble(key) ?? 1.0;
      }
    }

    // 1. WAS: exakte Phrase
    if (what.isNotEmpty) {
      String cleanedWhat = what
          .replaceAll(RegExp(r'[“”„‟]'), '"')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      googleDork = (cleanedWhat.contains(' ') && !cleanedWhat.contains('"'))
          ? '"$cleanedWhat"'
          : cleanedWhat;
    }

    // 1.1 Lern-Boost: stark gewichtete Keywords
    final List<String> learnedBoosts = [];
    weights.forEach((key, weight) {
      if (key.startsWith('weight_kw_') && weight > 1.5) {
        learnedBoosts.add(key.replaceFirst('weight_kw_', ''));
      }
    });
    if (learnedBoosts.isNotEmpty) {
      googleDork += ' (${learnedBoosts.take(3).join(' OR ')})';
    }

    // 2. WARUM: Kontext-Keywords als einfache Begriffe (NICHT allintext:,
    // weil das mit nachfolgenden site:/filetype: Operatoren kollidiert).
    if (why.isNotEmpty) {
      final contextKeywords = why
          .split(RegExp(r'[,;\s]+'))
          .where((kw) => kw.length > 2)
          .toList();
      if (contextKeywords.isNotEmpty) {
        googleDork += ' ${contextKeywords.join(' ')}';
      }
    }

    // 3. Persoenliche Gewichtung
    final beruf = settings['beruf'];
    if (beruf is String && beruf.isNotEmpty) {
      googleDork += ' $beruf';
    }
    // KEIN fiktiver location:-Operator. PLZ als reiner Suchbegriff.
    final plz = settings['plz'];
    if (plz is String && plz.isNotEmpty && plz != '0') {
      googleDork += ' $plz';
    }

    // 4. Lern-optimierte Filter
    final Map<String, double> filterWeights = {};
    for (final f in filters) {
      filterWeights[f] = _getLearnedWeight('filter_$f', weights);
    }
    final sortedFilters = List<String>.from(filters)
      ..sort((a, b) => filterWeights[b]!.compareTo(filterWeights[a]!));

    for (final filter in sortedFilters) {
      if (filterWeights[filter]! >= 0.8) {
        if (sourceOperators.containsKey(filter)) {
          googleDork += sourceOperators[filter]!;
        }
        if (fileOperators.containsKey(filter)) {
          googleDork += fileOperators[filter]!;
        }
      }
    }

    // 5. Jugendschutz & Anti-Ads
    googleDork += ' ${noiseExclusions.join(' ')}';
    final isYouthActive = (settings['enableYouthProtection'] as bool?) ?? true;
    if (isYouthActive) {
      googleDork += ' ${explicitExclusions.join(' ')}';
    }

    return googleDork.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String buildSearchUrl(
      String query, String engine, Map<String, dynamic> settings) {
    String base;
    String params = '';
    final isYouthActive = (settings['enableYouthProtection'] as bool?) ?? true;

    switch (engine) {
      case 'bing':
        base = 'https://www.bing.com/search?q=';
        // Korrekter Bing-Parameter fuer SafeSearch.
        if (isYouthActive) params = '&safeSearch=Strict';
        break;
      case 'duckduckgo':
        base = 'https://duckduckgo.com/?q=';
        if (isYouthActive) params = '&kp=1';
        break;
      default:
        base = 'https://www.google.com/search?q=';
        // filter=1 = duplikate dedupliziert (hoehere Praezision).
        params = '&filter=1';
        if (isYouthActive) params += '&safe=active';
    }

    if (query.length > 1800) query = query.substring(0, 1790).trim();
    return base + Uri.encodeComponent(query) + params;
  }
}
