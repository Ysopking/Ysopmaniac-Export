import 'package:shared_preferences/shared_preferences.dart';

class FindUXQueryBuilder {
  // Mapping interner Filter auf Googles native 'Advanced Search' Operatoren
  final Map<String, String> sourceOperators = {
    'foren': ' (site:reddit.com OR site:stackoverflow.com OR inurl:forum OR inurl:community)',
    'reddit': ' site:reddit.com',
    'news': ' (site:spiegel.de OR site:zeit.de OR site:heise.de OR site:bbc.com)',
    'wikipedia': ' site:wikipedia.org',
    'offiziell': ' (site:.gov OR site:.edu OR site:.org)',
    'academic': ' (site:.edu OR site:.ac.uk OR inurl:scholar)',
    'video': ' site:youtube.com OR site:vimeo.com',
    'blogs': ' inurl:blog OR site:medium.com',
    'shops': ' (site:amazon.de OR site:ebay.de OR site:otto.de)',
    'social': ' (site:twitter.com OR site:facebook.com OR site:linkedin.com)',
  };

  final Map<String, String> fileOperators = {
    'pdf': ' filetype:pdf',
    'ppt': ' filetype:pptx OR filetype:ppt',
    'doc': ' filetype:docx OR filetype:doc',
    'xls': ' filetype:xlsx OR filetype:xls',
    'code': ' (site:github.com OR site:gitlab.com)',
    'images': ' filetype:jpg OR filetype:png',
  };

  // Google native exclusions für Jugendschutz und Rauschunterdrückung
  static const List<String> noiseExclusions = ['-inurl:ads', '-inurl:promo', '-intitle:sponsored'];
  static const List<String> explicitExclusions = ['-sex', '-porn', '-nude', '-gambling', '-betting'];

  Future<double> _getLearnedWeight(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble('weight_$key') ?? 1.0;
  }

  Future<String> buildQuery({
    required String what,
    required String why,
    required List<String> filters,
    required Map<String, dynamic> settings,
    String mode = 'standard'
  }) async {
    String googleDork = '';
    final prefs = await SharedPreferences.getInstance();

    // 1. WAS (Das exakte Suchziel - Google "exact phrase" logic)
    if (what.isNotEmpty) {
      String cleanedWhat = what.replaceAll(RegExp(r'[“”„‟]'), '"').replaceAll(RegExp(r'\s+'), ' ').trim();
      googleDork = (cleanedWhat.contains(' ') && !cleanedWhat.contains('"')) ? '"$cleanedWhat"' : cleanedWhat;
    }

    // 1.1 LERN-ERWEITERUNG: Stark gewichtete Keywords einfließen lassen (NEU)
    final List<String> learnedBoosts = [];
    final allKeys = prefs.getKeys();
    for (var key in allKeys) {
      if (key.startsWith('weight_kw_')) {
        final weight = prefs.getDouble(key) ?? 1.0;
        if (weight > 1.5) { // Nur bei hoher Relevanz
          learnedBoosts.add(key.replaceFirst('weight_kw_', ''));
        }
      }
    }
    if (learnedBoosts.isNotEmpty) {
      googleDork += ' (' + learnedBoosts.take(3).join(' OR ') + ')';
    }

    // 2. WARUM (Kontextuelle Erweiterung - Google "allintext" logic)
    if (why.isNotEmpty) {
      List<String> contextKeywords = why.split(RegExp(r'[,;\s]+')).where((kw) => kw.length > 2).toList();
      if (contextKeywords.isNotEmpty) {
        googleDork += ' allintext:${contextKeywords.join(' ')}';
      }
    }

    // 3. PERSÖNLICHE GEWICHTUNG (Googles native Standort/Beruf-Operatoren)
    if (settings['beruf'] != null && settings['beruf'].isNotEmpty) {
      googleDork += ' ${settings['beruf']}';
    }
    if (settings['plz'] != null && settings['plz'].isNotEmpty && settings['plz'] != '0') {
      googleDork += ' location:${settings['plz']}';
    }

    // 4. LERN-OPTIMIERTE FILTER (Nutzung von Googles 'site:' und 'filetype:')
    Map<String, double> filterWeights = {};
    for (var f in filters) {
      filterWeights[f] = await _getLearnedWeight('filter_$f');
    }

    List<String> sortedFilters = List.from(filters);
    sortedFilters.sort((a, b) => filterWeights[b]!.compareTo(filterWeights[a]!));

    for (var filter in sortedFilters) {
      // Nur Filter einbeziehen, die eine positive Google-Gewichtung (lokal gelernt) haben
      if (filterWeights[filter]! >= 0.8) {
        if (sourceOperators.containsKey(filter)) googleDork += sourceOperators[filter]!;
        if (fileOperators.containsKey(filter)) googleDork += fileOperators[filter]!;
      }
    }

    // 5. JUGENDSCHUTZ & ANTI-ADS (Googles native Exclusions)
    googleDork += ' ' + noiseExclusions.join(' ');
    final bool isYouthActive = settings['enableYouthProtection'] ?? true;
    if (isYouthActive) {
      googleDork += ' ' + explicitExclusions.join(' ');
    }

    return googleDork.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String buildSearchUrl(String query, String engine, Map<String, dynamic> settings) {
    String base;
    String params = '';
    final bool isYouthActive = settings['enableYouthProtection'] ?? true;

    switch (engine) {
      case 'bing':
        base = 'https://www.bing.com/search?q=';
        if (isYouthActive) params = '&adlt=strict';
        break;
      default:
        base = 'https://www.google.com/search?q=';
        // Google native Parameter für maximale Präzision und Jugendschutz
        params = '&filter=0'; // Verhindert das Weglassen "ähnlicher" Ergebnisse
        if (isYouthActive) params += '&safe=active';
    }

    if (query.length > 1800) query = query.substring(0, 1790).trim();
    return base + Uri.encodeComponent(query) + params;
  }
}
