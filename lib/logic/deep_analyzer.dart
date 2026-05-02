import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/findux_stopwords.dart';

/// Analysiert die aktuelle Suche und schlaegt 4 kontextuelle
/// Vertiefungsrichtungen vor — gewichtet nach den gelernten
/// Nutzerpraeferenzen (weight_kw_* + weight_filter_*).
///
/// Score-Formel pro GoalCluster:
///
///   score  = base                              (Ausgangswert 0.15–0.35)
///          + Σ kwWeight(token)  * 0.20         für Query-Token ∩ Cluster-Keywords
///          + Σ kwWeight(token)  * 0.08         für Top-12-User-Tokens ∩ Cluster-Keywords
///          + Σ (filterWeight-1) * 0.12         für Cluster-Filter mit filterWeight > 1.0
///
///   Prefix-Match: token passt auf keyword wenn
///     token.length >= 4 && keyword.startsWith(token)  ODER
///     keyword.length >= 4 && token.startsWith(keyword)
///
/// Ergebnis: top 4 sortiert nach Score (absteigend).
/// Gleichstaende werden per Zufall aufgeloest (keine stabile Reihenfolge
/// bei nahezu gleichem Score).
class DeepAnalyzer {
  // -------------------------------------------------------------------------
  // Ziel-Katalog
  // -------------------------------------------------------------------------

  static const List<_GoalCluster> _catalog = [
    _GoalCluster(
      label: 'Wissenschaftliche Studien',
      keywords: [
        'studie', 'studien', 'studie', 'forschung', 'wissenschaft',
        'analyse', 'statistik', 'evidenz', 'meta', 'review',
        'journal', 'paper', 'thesis', 'publikation', 'befund',
      ],
      filters: ['academic'],
      base: 0.30,
    ),
    _GoalCluster(
      label: 'Erfahrungsberichte & Community',
      keywords: [
        'erfahrung', 'bewertung', 'meinung', 'forum', 'community',
        'praxis', 'erlebnis', 'kommentar', 'nutzer', 'empfehlung',
        'tipps', 'feedback', 'reddit', 'gutefrage',
      ],
      filters: ['forum'],
      base: 0.22,
    ),
    _GoalCluster(
      label: 'Offizielle Quellen & Behoerden',
      keywords: [
        'gesetz', 'amt', 'behoerde', 'offiziell', 'regierung',
        'recht', 'vorschrift', 'paragraph', 'regelung', 'bund',
        'ministerium', 'bundesamt', 'verordnung', 'satzung',
      ],
      filters: ['official'],
      base: 0.28,
    ),
    _GoalCluster(
      label: 'Testberichte & Produktvergleiche',
      keywords: [
        'vergleich', 'test', 'bestenliste', 'ranking', 'check',
        'stiftung', 'warentest', 'chip', 'note', 'wertung',
        'sieger', 'empfehlung', 'qualitaet', 'bewertung',
      ],
      filters: ['ratgeber'],
      base: 0.25,
    ),
    _GoalCluster(
      label: 'Technische Dokumentation',
      keywords: [
        'anleitung', 'dokumentation', 'tutorial', 'howto', 'install',
        'konfiguration', 'fehler', 'api', 'github', 'stack',
        'code', 'programmierung', 'developer', 'spec', 'referenz',
      ],
      filters: ['docs'],
      base: 0.22,
    ),
    _GoalCluster(
      label: 'Aktuelle Nachrichten',
      keywords: [
        'aktuell', 'news', 'heute', 'neu', 'meldung', 'ticker',
        'pressemitteilung', 'update', 'ankuendigung', 'aktuelles',
        'bericht', 'nachricht', 'jetzt', 'live', 'breaking',
      ],
      filters: ['news'],
      base: 0.20,
    ),
    _GoalCluster(
      label: 'Guenstigste Anbieter & Preise',
      keywords: [
        'preis', 'guenstig', 'angebot', 'rabatt', 'kaufen', 'shop',
        'billig', 'sparen', 'deal', 'kosten', 'versand', 'amazon',
        'ebay', 'preisvergleich', 'angebote',
      ],
      filters: ['shopping'],
      base: 0.20,
    ),
    _GoalCluster(
      label: 'Ratgeber & Erklaerungen',
      keywords: [
        'ratgeber', 'erklaerung', 'leitfaden', 'hilfe', 'antwort',
        'fragen', 'guide', 'grundlagen', 'bedeutung', 'definition',
        'was_ist', 'wie_funktioniert', 'warum', 'ueberblick',
      ],
      filters: ['ratgeber', 'wikipedia'],
      base: 0.25,
    ),
    _GoalCluster(
      label: 'Soziale Leistungen & Foerderung',
      keywords: [
        'sozial', 'hilfe', 'unterstuetzung', 'leistung', 'antrag',
        'buergergeld', 'kindergeld', 'rente', 'wohngeld', 'foerderung',
        'zuschuss', 'steuer', 'steuererklaerung', 'beantragen',
      ],
      filters: ['official'],
      base: 0.28,
    ),
    _GoalCluster(
      label: 'Gesundheit & Medizin',
      keywords: [
        'gesundheit', 'krank', 'medizin', 'arzt', 'symptom',
        'behandlung', 'therapie', 'medikament', 'diagnose', 'ursache',
        'heilung', 'krankheit', 'vorsorge', 'ernaehrung',
      ],
      filters: ['academic', 'official'],
      base: 0.26,
    ),
    _GoalCluster(
      label: 'Nachhaltige Alternativen',
      keywords: [
        'nachhaltig', 'oeko', 'umwelt', 'bio', 'alternativ',
        'recycling', 'second', 'hand', 'fair', 'klimaneutral',
        'plastikfrei', 'regional', 'repair', 'upcycling',
      ],
      filters: [],
      base: 0.16,
    ),
    _GoalCluster(
      label: 'Hintergrund & Analyse',
      keywords: [
        'hintergrund', 'zusammenhang', 'analyse', 'kontext', 'ursache',
        'folge', 'auswirkung', 'verstaendnis', 'tiefe', 'recherche',
        'detail', 'erklaert', 'einordnung', 'perspektive',
      ],
      filters: ['academic', 'news'],
      base: 0.22,
    ),
  ];

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Gibt 4 Vertiefungsrichtungen fuer [query] zurueck, personalisiert
  /// durch die gelernten SharedPreferences-Gewichte.
  ///
  /// [weights] ist aus Abwaertskompatibilitaet erhalten, wird aber
  /// ignoriert — die Gewichte werden direkt aus SharedPreferences gelesen
  /// damit der Caller keine internen Zustaende weiterreichen muss.
  static Future<List<String>> analyzeResults(
    String query,
    Map<String, double> weights, {
    String language = 'de',
  }) async {
    // 1. Gelernte Gewichte aus SharedPreferences laden
    final Map<String, double> kwWeights = {};
    final Map<String, double> filterWeights = {};
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys()) {
        if (key.startsWith('weight_kw_')) {
          kwWeights[key.substring('weight_kw_'.length)] =
              prefs.getDouble(key) ?? 1.0;
        } else if (key.startsWith('weight_filter_')) {
          filterWeights[key.substring('weight_filter_'.length)] =
              prefs.getDouble(key) ?? 1.0;
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('DeepAnalyzer: prefs read failed: $e');
    }

    // 2. Query tokenisieren (Stoppwoerter entfernen, >= 3 Zeichen)
    final stopwords = stopwordsForLanguage(language);
    final queryTokens = _tokenize(query, stopwords);

    // 3. Top-12 User-Tokens (hoechstes Gewicht > 1.0, gelernte Affinitaet)
    final topUserTokens = kwWeights.entries
        .where((e) => e.value > 1.0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top12 = topUserTokens.take(12).map((e) => e.key).toSet();

    // 4. Score pro Cluster
    final rng = math.Random();
    final scored = _catalog.map((cluster) {
      double score = cluster.base;

      // Query-Token-Treffer: direkter Kontext (hoeher gewichtet)
      for (final token in queryTokens) {
        for (final kw in cluster.keywords) {
          if (_prefixMatch(token, kw)) {
            // kwWeight fuer diesen Token falls vorhanden, sonst Basis 0.15
            score += (kwWeights[token] ?? 0.15) * 0.20;
          }
        }
      }

      // Top-User-Token-Treffer: gelernte Praeferenzen
      for (final token in top12) {
        for (final kw in cluster.keywords) {
          if (_prefixMatch(token, kw)) {
            score += (kwWeights[token] ?? 1.0) * 0.08;
          }
        }
      }

      // Filter-Bonus: Cluster-Filter vom User bevorzugt?
      for (final filter in cluster.filters) {
        final fw = filterWeights[filter];
        if (fw != null && fw > 1.0) {
          score += (fw - 1.0) * 0.12;
        }
      }

      // Kleines Rauschen fuer Gleichstand-Aufloessung (unsichtbar)
      score += rng.nextDouble() * 0.001;

      return _ScoredCluster(cluster.label, score);
    }).toList();

    // 5. Absteigend sortieren, Top 4 zurueckgeben
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(4).map((c) => c.label).toList();
  }

  // -------------------------------------------------------------------------
  // Hilfsmethoden
  // -------------------------------------------------------------------------

  /// Tokenisiert [input]: Kleinschreibung, nur Wortzeichen + Umlaute,
  /// Stoppwoerter entfernen, Mindestlaenge 3.
  static List<String> _tokenize(String input, Set<String> stopwords) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^\wäöüß]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.length >= 3 && !stopwords.contains(t))
        .toList();
  }

  /// Prefix-Match: passt wenn token auf kw beginnt ODER kw auf token
  /// (beide Richtungen), Mindestlaenge 4 fuer den Praefixgeber.
  static bool _prefixMatch(String token, String kw) {
    if (token.length >= 4 && kw.startsWith(token)) return true;
    if (kw.length >= 4 && token.startsWith(kw)) return true;
    return false;
  }
}

// ---------------------------------------------------------------------------
// Interne Datenstrukturen
// ---------------------------------------------------------------------------

class _GoalCluster {
  final String label;
  final List<String> keywords;
  final List<String> filters;
  final double base;
  const _GoalCluster({
    required this.label,
    required this.keywords,
    required this.filters,
    required this.base,
  });
}

class _ScoredCluster {
  final String label;
  final double score;
  const _ScoredCluster(this.label, this.score);
}
