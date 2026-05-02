import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reduzierte Repraesentation eines Such-Treffers aus dem importierten
/// Browser-Verlauf. Bewusst minimalistisch: keine URL, keine Zeitstempel,
/// nur Wochen-Bucket. Nur diese 4 Felder verlassen je den Reduktions-Schritt.
class HistoryTriple {
  final String query;
  final String domain;
  final String title;
  final String week; // YYYY-Www

  HistoryTriple({
    required this.query,
    required this.domain,
    required this.title,
    required this.week,
  });

  Map<String, dynamic> toMap() => {
        'q': query,
        'd': domain,
        't': title,
        'w': week,
      };

  factory HistoryTriple.fromMap(Map m) => HistoryTriple(
        query: (m['q'] ?? '').toString(),
        domain: (m['d'] ?? '').toString(),
        title: (m['t'] ?? '').toString(),
        week: (m['w'] ?? '').toString(),
      );
}

class _RawEntry {
  final String url;
  final String title;
  final DateTime time;
  _RawEntry(this.url, this.title, this.time);
}

class ImportSummary {
  final int rawCount;
  final int tripleCount;
  final List<HistoryTriple> samples;
  final List<HistoryTriple> all;
  ImportSummary({
    required this.rawCount,
    required this.tripleCount,
    required this.samples,
    required this.all,
  });
}

/// Chrome-Verlauf-Import — Zero-Server, alles offline.
///
/// Ablauf:
/// 1. analyzeFile(path): Datei lesen (lokal), parsen, reduzieren auf
///    {query, domain, title, week}-Triples. Datei wird sofort danach
///    geloescht. Liefert eine Vorschau (samples + all).
/// 2. persistAndApply(summary.all, box): Triples verschluesselt
///    (HiveAesCipher) in Box `imported_chronicle` speichern (max 1000)
///    und sehr milde Lern-Bumps auf `weight_kw_<wort>` /
///    `weight_domain_<host>` in SharedPreferences anwenden.
///
/// Stage G: Akzeptiert jetzt auch Google-Takeout-ZIPs direkt — sucht
/// darin Verlauf.json / BrowserHistory.json / History.json.
class ChromeImportService {
  static const String _boxName = 'imported_chronicle';
  static const int _maxTriples = 1000;
  static const Duration _landingWindow = Duration(minutes: 10);

  // ---------- Anti-Infiltration Limits ----------
  /// Datei groesser als 50 MB wird ohne Parsen verworfen.
  static const int _maxFileBytes = 50 * 1024 * 1024;
  /// Stage G: ZIP-Inhalt nach Entpacken max 100 MB (Anti-ZIP-Bombe).
  static const int _maxUnzippedBytes = 100 * 1024 * 1024;
  /// Mehr als 200_000 Roh-Eintraege werden hart abgeschnitten.
  static const int _maxRawEntries = 200000;
  /// URL laenger als 2000 Zeichen -> Eintrag verworfen.
  static const int _maxUrlLen = 2000;
  /// Query laenger als 200 Zeichen -> Eintrag verworfen.
  static const int _maxQueryLen = 200;
  /// Domain laenger als 253 Zeichen oder mit Sonderzeichen -> verworfen.
  static const int _maxDomainLen = 253;
  static final RegExp _domainOk =
      RegExp(r'^[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?)+$');
  /// Pro Import maximal 100 unique Keyword-Bumps.
  static const int _maxKwBumpsPerImport = 100;
  /// Pro Import maximal 50 unique Domain-Bumps.
  static const int _maxDomainBumpsPerImport = 50;

  // gleiche Hard-Limits wie LearningService
  static const double _kwMin = 0.4;
  static const double _kwMax = 2.5;
  static const double _domainMin = 0.1;
  static const double _domainMax = 5.0;
  // Import = manuelles, soft-positives Signal -> sehr kleine Bumps
  static const double _kwBump = 0.05;
  static const double _domainBump = 0.10;

  /// Map<host, queryParam> — bekannte SERP-Engines
  static const Map<String, String> _serpEngines = {
    'google.com': 'q',
    'google.de': 'q',
    'google.at': 'q',
    'google.ch': 'q',
    'google.co.uk': 'q',
    'google.fr': 'q',
    'google.es': 'q',
    'google.it': 'q',
    'google.nl': 'q',
    'google.be': 'q',
    'google.pl': 'q',
    'bing.com': 'q',
    'duckduckgo.com': 'q',
    'startpage.com': 'query',
    'search.brave.com': 'q',
    'brave.com': 'q',
    'ecosia.org': 'q',
    'yahoo.com': 'p',
    'qwant.com': 'q',
    'kagi.com': 'q',
    'mojeek.com': 'q',
    'yandex.com': 'text',
    'yandex.ru': 'text',
    'metager.de': 'eingabe',
    'metager.org': 'eingabe',
  };

  static Future<Box<dynamic>> openBox(List<int> cipherKey) async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box<dynamic>(_boxName);
    return await Hive.openBox<dynamic>(
      _boxName,
      encryptionCipher: HiveAesCipher(cipherKey),
    );
  }

  // ---------- Stage G: ZIP-Extraction ----------

  /// Sucht in einem Google-Takeout-ZIP die History-JSON. Erkennt:
  /// - Verlauf.json   (DE-Locale)
  /// - BrowserHistory.json / History.json
  /// - Generell: jede *.json unter einem Ordner ".../Chrome/..."
  ///
  /// Anti-DoS: ungepackter Inhalt > 100 MB -> abgewiesen (Zip-Bombe).
  /// Liefert leeren String wenn nichts Brauchbares gefunden.
  static String _extractTakeoutJson(List<int> zipBytes) {
    try {
      final archive = ZipDecoder().decodeBytes(zipBytes, verify: false);

      // 1) Anti-ZIP-Bombe: Summe der unkomprimierten Groessen pruefen
      var total = 0;
      for (final f in archive.files) {
        if (f.isFile) total += f.size;
        if (total > _maxUnzippedBytes) {
          debugPrint('ZIP rejected: uncompressed size > limit');
          return '';
        }
      }

      // 2) Wunschdateien in Prioritaets-Reihenfolge
      const preferredNames = <String>[
        'verlauf.json',
        'browserhistory.json',
        'history.json',
      ];

      ArchiveFile? best;
      var bestRank = 99;
      for (final f in archive.files) {
        if (!f.isFile) continue;
        final lower = f.name.toLowerCase();
        if (!lower.endsWith('.json')) continue;
        if (!lower.contains('chrome')) continue;

        // Bevorzugte Namen erkennen
        final base = lower.split('/').last;
        var rank = 50;
        for (var i = 0; i < preferredNames.length; i++) {
          if (base == preferredNames[i]) {
            rank = i;
            break;
          }
        }
        if (rank < bestRank) {
          best = f;
          bestRank = rank;
        }
      }

      if (best == null) {
        debugPrint('ZIP: no Chrome history JSON found');
        return '';
      }

      final raw = best.content;
      if (raw is List<int>) {
        return utf8.decode(raw, allowMalformed: true);
      }
      return raw.toString();
    } catch (e) {
      debugPrint('ZIP decode failed: $e');
      return '';
    }
  }

  // ---------- Parser ----------

  static List<_RawEntry> _parseTakeoutJson(String content) {
    final out = <_RawEntry>[];
    if (content.trim().isEmpty) return out;
    try {
      final decoded = json.decode(content);
      if (decoded is! Map) return out;
      final entries = decoded['Browser History'] ??
          decoded['browser_history'] ??
          decoded['History'] ??
          decoded['Browser-Verlauf'] ??
          const [];
      if (entries is! List) return out;
      for (final e in entries) {
        if (out.length >= _maxRawEntries) break;
        if (e is! Map) continue;
        final url = (e['url'] ?? '').toString();
        if (url.isEmpty || url.length > _maxUrlLen) continue;
        // Nur http(s) — keine file://, javascript:, data:, chrome://
        final lo = url.toLowerCase();
        if (!lo.startsWith('http://') && !lo.startsWith('https://')) continue;
        final title = (e['title'] ?? '').toString();
        final t = e['time_usec'] ?? e['time'] ?? e['timestamp'];
        if (t == null) continue;
        DateTime? dt = _parseTime(t);
        if (dt == null) continue;
        out.add(_RawEntry(url, title, dt));
      }
    } catch (e) {
      debugPrint('ChromeImport.parseJson: $e');
    }
    return out;
  }

  static DateTime? _parseTime(dynamic t) {
    int? v;
    if (t is int) {
      v = t;
    } else if (t is String) {
      v = int.tryParse(t);
    }
    if (v == null || v <= 0) return null;
    // Chrome time_usec = us seit 1601-01-01
    if (v > 13000000000000000) {
      final unixUs = v - 11644473600000000;
      return DateTime.fromMicrosecondsSinceEpoch(unixUs);
    }
    if (v > 1000000000000000) {
      // unix microseconds
      return DateTime.fromMicrosecondsSinceEpoch(v);
    }
    if (v > 1000000000000) {
      // unix milliseconds
      return DateTime.fromMillisecondsSinceEpoch(v);
    }
    if (v > 1000000000) {
      // unix seconds
      return DateTime.fromMillisecondsSinceEpoch(v * 1000);
    }
    return null;
  }

  /// Best-effort fuer Chrome / Firefox HTML-Export (Lesezeichen).
  static List<_RawEntry> _parseHtmlExport(String content) {
    final out = <_RawEntry>[];
    final aRe = RegExp(r'<a\s+([^>]*?)>([^<]*)</a>', caseSensitive: false);
    final hrefRe = RegExp(r'''href="([^"]+)"''', caseSensitive: false);
    final dateRe = RegExp(
        r'''(?:add_date|last_visit|time_added|last_modified)="(\d+)"''',
        caseSensitive: false);
    for (final m in aRe.allMatches(content)) {
      if (out.length >= _maxRawEntries) break;
      final attrs = m.group(1) ?? '';
      final title = (m.group(2) ?? '').trim();
      final hrefM = hrefRe.firstMatch(attrs);
      if (hrefM == null) continue;
      final url = hrefM.group(1) ?? '';
      if (url.isEmpty || url.length > _maxUrlLen) continue;
      final lo = url.toLowerCase();
      if (!lo.startsWith('http://') && !lo.startsWith('https://')) continue;
      final dateM = dateRe.firstMatch(attrs);
      DateTime? dt;
      if (dateM != null) {
        dt = _parseTime(dateM.group(1));
      }
      dt ??= DateTime.now();
      out.add(_RawEntry(url, title, dt));
    }
    return out;
  }

  // ---------- Reduce ----------

  static String _normalizeHost(String h) {
    var x = h.toLowerCase();
    if (x.startsWith('www.')) x = x.substring(4);
    return x;
  }

  static String? _extractSerpQuery(Uri u) {
    final host = _normalizeHost(u.host);
    final param = _serpEngines[host];
    if (param == null) return null;
    // Google: nur /search-Pfad (sonst /maps, /flights, /shopping etc.)
    if (host.startsWith('google.') && !u.path.startsWith('/search')) {
      return null;
    }
    final q = u.queryParameters[param];
    if (q == null) return null;
    final t = q.trim();
    if (t.isEmpty || t.length > 200) return null;
    return t;
  }

  static String _isoWeek(DateTime dt) {
    final dow = dt.weekday; // 1..7 (Mo..So)
    final thursday = dt.add(Duration(days: 4 - dow));
    final yearStart = DateTime(thursday.year, 1, 1);
    final week = ((thursday.difference(yearStart).inDays) / 7).floor() + 1;
    return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
  }

  static bool _domainSafe(String d) {
    if (d.isEmpty) return true; // leer = "keine landing", auch ok
    if (d.length > _maxDomainLen) return false;
    return _domainOk.hasMatch(d);
  }

  static List<HistoryTriple> _reduceToTriples(List<_RawEntry> raw) {
    raw.sort((a, b) => a.time.compareTo(b.time));
    final triples = <HistoryTriple>[];
    final seen = <String>{};

    for (int i = 0; i < raw.length; i++) {
      final e = raw[i];
      final url = Uri.tryParse(e.url);
      if (url == null) continue;
      final query = _extractSerpQuery(url);
      if (query == null) continue;
      // Anti-Infiltration: Query muss sauber sein
      if (query.length > _maxQueryLen) continue;
      if (query.codeUnits.any((c) => c < 32 && c != 9)) continue;

      // Erste echte Landing innerhalb der Session-Window
      String landingDomain = '';
      String landingTitle = '';
      for (int j = i + 1; j < raw.length; j++) {
        final n = raw[j];
        if (n.time.difference(e.time) > _landingWindow) break;
        final nu = Uri.tryParse(n.url);
        if (nu == null) continue;
        if (nu.scheme != 'http' && nu.scheme != 'https') continue;
        final nh = _normalizeHost(nu.host);
        if (nh.isEmpty) continue;
        if (!_domainSafe(nh)) continue;
        if (_serpEngines.containsKey(nh)) continue;
        landingDomain = nh;
        landingTitle = n.title;
        break;
      }

      final qNorm = query.toLowerCase();
      final key = '$qNorm|$landingDomain';
      if (seen.contains(key)) continue;
      seen.add(key);

      final cleanTitle =
          landingTitle.length > 120 ? landingTitle.substring(0, 120) : landingTitle;

      triples.add(HistoryTriple(
        query: query,
        domain: landingDomain,
        title: cleanTitle,
        week: _isoWeek(e.time),
      ));
    }
    return triples;
  }

  // ---------- Public API ----------

  /// Liest Datei lokal, reduziert und LOESCHT die Datei in jedem Fall.
  /// Persistiert noch NICHT (User entscheidet via persistAndApply).
  ///
  /// Stage G: Wenn die Datei `.zip` heisst, wird sie als Google Takeout
  /// behandelt — Verlauf.json (oder BrowserHistory.json) wird im Memory
  /// extrahiert und durch den JSON-Parser gejagt.
  static Future<ImportSummary> analyzeFile(String filePath) async {
    final f = File(filePath);
    String content = '';
    final lower = filePath.toLowerCase();
    final isZip = lower.endsWith('.zip');
    try {
      if (await f.exists()) {
        final size = await f.length();
        if (size > _maxFileBytes) {
          debugPrint('ChromeImport.skip: file too large ($size bytes)');
          // Datei trotzdem loeschen unten
        } else if (isZip) {
          // ZIP -> Bytes lesen, History-JSON darin extrahieren
          final bytes = await f.readAsBytes();
          content = _extractTakeoutJson(bytes);
        } else {
          content = await f.readAsString();
        }
      }
    } catch (e) {
      debugPrint('ChromeImport.read: $e');
    }

    List<_RawEntry> raw = const [];
    try {
      if (isZip || lower.endsWith('.json')) {
        raw = _parseTakeoutJson(content);
      } else if (lower.endsWith('.html') || lower.endsWith('.htm')) {
        raw = _parseHtmlExport(content);
      } else {
        // Unbekannte Endung -> beide Formate probieren
        raw = _parseTakeoutJson(content);
        if (raw.isEmpty) raw = _parseHtmlExport(content);
      }
    } catch (e) {
      debugPrint('ChromeImport.parse: $e');
    }

    final triples = _reduceToTriples(raw);

    // Datei-Loeschung ist garantiert (auch bei Parse-Fehler)
    try {
      if (await f.exists()) await f.delete();
    } catch (e) {
      debugPrint('ChromeImport.delete: $e');
    }
    // GC-Hint: grosser String darf jetzt freigegeben werden
    // (Dart-GC wird das ohnehin tun, sobald die Funktion zurueckkehrt)
    // ignore: unused_local_variable
    content = '';

    return ImportSummary(
      rawCount: raw.length,
      tripleCount: triples.length,
      samples: triples.take(3).toList(),
      all: triples,
    );
  }

  /// Speichert Triples (verschluesselt, dedup, max 1000) und bumpt
  /// Lern-Gewichte mild.
  static Future<void> persistAndApply(
    List<HistoryTriple> triples,
    Box<dynamic> importBox,
  ) async {
    if (triples.isEmpty) return;

    final existing = <HistoryTriple>[];
    for (final v in importBox.values) {
      if (v is Map) existing.add(HistoryTriple.fromMap(v));
    }

    // Bestehende + neue, dedup nach (query|domain), neueste am Ende
    final all = [...existing, ...triples];
    final seen = <String>{};
    final dedup = <HistoryTriple>[];
    for (final t in all) {
      final k = '${t.query.toLowerCase()}|${t.domain}';
      if (seen.contains(k)) continue;
      seen.add(k);
      dedup.add(t);
    }
    final keep = dedup.length > _maxTriples
        ? dedup.sublist(dedup.length - _maxTriples)
        : dedup;

    await importBox.clear();
    for (int i = 0; i < keep.length; i++) {
      await importBox.put(i, keep[i].toMap());
    }

    // Lern-Bumps in SharedPreferences (gleiche Keys wie LearningService)
    // Mit Per-Import-Caps gegen "Modell-Vergiftung" durch praeparierte Files.
    final prefs = await SharedPreferences.getInstance();
    const stop = <String>{
      'und', 'oder', 'aber', 'mit', 'fuer', 'fur', 'von', 'zum', 'der',
      'die', 'das', 'den', 'dem', 'des', 'ein', 'eine', 'einen', 'einer',
      'eines', 'ist', 'sind', 'war', 'als', 'wie', 'was', 'wer', 'wann',
      'auf', 'bei', 'aus', 'nach', 'auch', 'noch', 'nur', 'sich', 'man',
      'the', 'and', 'for', 'with', 'this', 'that', 'from', 'are',
      'how', 'why', 'who', 'when', 'where', 'what',
    };

    // Recency-gewichtetes Scoring: neuere Eintraege zaehlen mehr als alte.
    // Recency-Multiplikator: ≤4 Wochen=1.0, 5-12=0.60, 13-26=0.30, >26=0.15
    final now = DateTime.now();
    final nowYear = now.year;
    final nowDow = now.weekday;
    final nowThursday = now.add(Duration(days: 4 - nowDow));
    final nowYearStart = DateTime(nowThursday.year, 1, 1);
    final nowWeekNum = ((nowThursday.difference(nowYearStart).inDays) ~/ 7) + 1;
    final nowAbsWeek = nowThursday.year * 52 + nowWeekNum;

    double _recency(String week) {
      try {
        final p = week.split('-W');
        if (p.length != 2) return 0.30;
        final wYear = int.parse(p[0]);
        final wNum = int.parse(p[1]);
        final weeksAgo = nowAbsWeek - (wYear * 52 + wNum);
        if (weeksAgo <= 4) return 1.00;
        if (weeksAgo <= 12) return 0.60;
        if (weeksAgo <= 26) return 0.30;
        return 0.15;
      } catch (_) { return 0.30; }
    }

    // Recency-gewichteter Score pro Keyword und Domain
    final kwScores = <String, double>{};
    final domainScores = <String, double>{};
    for (final t in triples) {
      final r = _recency(t.week);
      final words = t.query
          .toLowerCase()
          .replaceAll(RegExp(r'["\(\)\[\]]'), ' ')
          .replaceAll(RegExp(r'-\S+'), ' ')
          .replaceAll(RegExp(r'[^\w\s]'), ' ')
          .split(RegExp(r'\s+'))
          .where((w) => w.length >= 4 && w.length <= 32 && !stop.contains(w))
          .toSet();
      for (final w in words) {
        kwScores[w] = (kwScores[w] ?? 0) + r;
      }
      if (t.domain.isNotEmpty && _domainSafe(t.domain)) {
        domainScores[t.domain] = (domainScores[t.domain] ?? 0) + r;
      }
    }

    // Sortiert nach gewichtetem Score absteigend, dann Top-N bumpen
    final topKws = kwScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topDomains = domainScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Bump-Skalierung: Basis * clamp(score/3.0, 1.0, 3.0)
    // Haeufige+aktuelle Keywords bekommen bis zu 3x den Basis-Bump.
    for (final e in topKws.take(_maxKwBumpsPerImport)) {
      final scale = (e.value / 3.0).clamp(1.0, 3.0);
      final k = 'weight_kw_${e.key}';
      final cur = prefs.getDouble(k) ?? 1.0;
      final next = (cur + _kwBump * scale).clamp(_kwMin, _kwMax);
      await prefs.setDouble(k, next);
    }
    for (final e in topDomains.take(_maxDomainBumpsPerImport)) {
      final scale = (e.value / 3.0).clamp(1.0, 3.0);
      final k = 'weight_domain_${e.key}';
      final cur = prefs.getDouble(k) ?? 1.0;
      final next = (cur + _domainBump * scale).clamp(_domainMin, _domainMax);
      await prefs.setDouble(k, next);
    }
  }

  /// Stage G: Bump-Helper fuer das Interessen-Feature  /// Stage G: Bump-Helper fuer das Interessen-Feature. Jedes Token
  /// (top-cat, sub-cat, item) wird einzeln als weight_kw_<token>
  /// gebumpt. Bewusst auch fuer kurze Tokens (>=3 Zeichen), weil
  /// "Rap" oder "EDM" kuerzer sind als das normale Verlaufs-Filter.
  static Future<void> applyInterestBumps(List<String> paths) async {
    if (paths.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final tokens = <String>{};
    for (final p in paths) {
      for (final t in p.split('/')) {
        final clean = t
            .toLowerCase()
            .replaceAll(RegExp(r'[^\w\s]'), ' ')
            .trim()
            .replaceAll(RegExp(r'\s+'), ' ');
        for (final w in clean.split(' ')) {
          if (w.length >= 3 && w.length <= 32) tokens.add(w);
        }
      }
    }
    // Kappung: max 100 Bumps pro Save-Aktion (gleiche Logik wie Import)
    final list = tokens.take(_maxKwBumpsPerImport);
    for (final w in list) {
      final k = 'weight_kw_$w';
      final cur = prefs.getDouble(k) ?? 1.0;
      // Etwas hoeherer Bump als Auto-Import, weil der User explizit
      // angegeben hat — aber immer noch sehr mild.
      final next = (cur + 0.10).clamp(_kwMin, _kwMax);
      await prefs.setDouble(k, next);
    }
  }

  static Future<void> clearImported(Box<dynamic> importBox) async {
    await importBox.clear();
  }

  static int countImported(Box<dynamic> importBox) => importBox.length;

  static List<String> topImportedDomains(
    Box<dynamic> importBox, {
    int limit = 5,
  }) {
    final counts = <String, int>{};
    for (final v in importBox.values) {
      if (v is Map) {
        final d = (v['d'] ?? '').toString();
        if (d.isNotEmpty) counts[d] = (counts[d] ?? 0) + 1;
      }
    }
    final list = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return list.take(limit).map((e) => e.key).toList();
  }
}
