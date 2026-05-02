import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/findux_stopwords.dart';

/// Lern- und Gewichtungs-Modul (v3, Coach-aware).
///
/// Was getrackt wird (alles verschluesselt, lokal):
///   - Suchanfragen: query+url+filter+mode+sources+files+stammdaten-snapshot
///                   + coach_choices (Theme, Dimension, Chip-Label, Tags)
///   - Feedback: thumbs up/down + optionaler Kommentar (idempotent pro search)
///
/// Wie gewichtet wird (lokale Gewichte in SharedPreferences):
///   - weight_kw_<wort>      Keyword-Gewicht
///   - weight_filter_<f>     Quellen-/Datei-Filter
///   - weight_mode_<m>       precise/standard/discover/recent
///   - weight_domain_<host>  bevorzugte/abgewertete Domains
///   - weight_employment_<t> Beschaeftigungstyp-Korrelation
///   - weight_theme_<id>     Coach-Themen-Gewicht
///   - weight_chip_<id>      Coach-Chip-Gewicht (theme:dim:chip)
class LearningService {
  static const String _boxName = 'learning_data';
  static const String _logBoxName = 'learning_log';
  static const String _feedbackBoxName = 'learning_feedback';

  static const double _decayFactor = 0.05;
  static const int _maxSearchLogEntries = 200;

  static const double _bumpUp = 0.20;
  static const double _bumpDown = 0.25;

  static const double _kwMin = 0.4;
  static const double _kwMax = 2.5;
  static const double _filterMin = 0.2;
  static const double _filterMax = 4.0;
  static const double _modeMin = 0.3;
  static const double _modeMax = 3.0;
  static const double _domainMin = 0.1;
  static const double _domainMax = 5.0;
  static const double _themeMin = 0.3;
  static const double _themeMax = 3.0;
  static const double _chipMin = 0.3;
  static const double _chipMax = 3.0;

  bool _initialized = false;

  Future<void> init(List<int> cipherKey) async {
    if (_initialized) return;
    final cipher = HiveAesCipher(cipherKey);
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox<dynamic>(_boxName, encryptionCipher: cipher);
    }
    if (!Hive.isBoxOpen(_logBoxName)) {
      await Hive.openBox<dynamic>(_logBoxName, encryptionCipher: cipher);
    }
    if (!Hive.isBoxOpen(_feedbackBoxName)) {
      await Hive.openBox<dynamic>(_feedbackBoxName, encryptionCipher: cipher);
    }
    _initialized = true;
  }

  Future<void> trackSearch({
    required String query,
    required String url,
    required Map<String, dynamic> settings,
    required List<String> sources,
    required List<String> files,
    required String mode,
    List<Map<String, dynamic>>? coachChoices,
  }) async {
    if (!Hive.isBoxOpen(_boxName)) return;
    final box = Hive.box<dynamic>(_boxName);
    final key = DateTime.now().millisecondsSinceEpoch.toString();
    await box.put(key, <String, dynamic>{
      'query': query,
      'url': url,
      'engine': (settings['searchengine'] as String?) ?? 'google',
      'employmentType':
          (settings['employmentType'] as String?) ?? 'student',
      'language': (settings['language'] as String?) ?? 'de',
      'timestamp': DateTime.now().toIso8601String(),
      'sources': sources,
      'files': files,
      'mode': mode,
      if (coachChoices != null && coachChoices.isNotEmpty)
        'coach_choices': coachChoices,
    });
    await _rotateLog(box);
  }

  Future<void> trackFeedback(String rating, {String? comment}) async {
    if (!Hive.isBoxOpen(_feedbackBoxName) ||
        !Hive.isBoxOpen(_boxName)) return;
    final box = Hive.box<dynamic>(_feedbackBoxName);
    final searchBox = Hive.box<dynamic>(_boxName);

    if (searchBox.isEmpty) return;
    final lastSearchId = searchBox.keys.last.toString();

    final existing = box.values.cast<dynamic>().firstWhere(
          (e) {
            if (e is! Map) return false;
            return e['search_id']?.toString() == lastSearchId;
          },
          orElse: () => null,
        );
    if (existing != null) {
      final m = Map<String, dynamic>.from(existing as Map);
      m['comment'] = comment ?? m['comment'] ?? '';
      for (final k in box.keys) {
        final v = box.get(k);
        if (v is Map && v['search_id']?.toString() == lastSearchId) {
          await box.put(k, m);
          break;
        }
      }
      return;
    }

    final key = DateTime.now().millisecondsSinceEpoch.toString();
    await box.put(key, <String, dynamic>{
      'search_id': lastSearchId,
      'rating': rating,
      'comment': comment ?? '',
      'timestamp': DateTime.now().toIso8601String(),
      'applied': false,
    });
  }

  Future<void> checkAndAnalyze() async {
    final prefs = await SharedPreferences.getInstance();
    final lastAnalysis = prefs.getInt('last_analysis') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - lastAnalysis > 7 * 24 * 60 * 60 * 1000) {
      await _analyzeAndOptimize(prefs);
      await _applyDecay(prefs);
      await prefs.setInt('last_analysis', now);
    }
  }

  Future<void> _analyzeAndOptimize(SharedPreferences prefs) async {
    if (!Hive.isBoxOpen(_boxName) ||
        !Hive.isBoxOpen(_feedbackBoxName)) return;
    final searchBox = Hive.box<dynamic>(_boxName);
    final feedbackBox = Hive.box<dynamic>(_feedbackBoxName);

    final searchData = Map<dynamic, dynamic>.from(searchBox.toMap());

    final pendingKeys = <dynamic>[];
    for (final k in feedbackBox.keys) {
      final v = feedbackBox.get(k);
      if (v is Map && v['applied'] != true) pendingKeys.add(k);
    }

    int processed = 0;
    for (final fk in pendingKeys) {
      final fValue = Map<String, dynamic>.from(feedbackBox.get(fk) as Map);
      final searchId = fValue['search_id'];
      final rating = fValue['rating'] as String?;
      if (searchId == null || rating == null) continue;
      if (!searchData.containsKey(searchId)) continue;

      final search = Map<String, dynamic>.from(searchData[searchId] as Map);
      final isPositive = rating == 'up';
      final delta = isPositive ? _bumpUp : -_bumpDown;
      final kwDelta = delta * 0.5;

      final mode = (search['mode'] as String?) ?? 'standard';
      await _bumpAdditive(prefs, 'weight_mode_$mode', delta, _modeMin, _modeMax);

      final sources =
          (search['sources'] as List<dynamic>?) ?? const <dynamic>[];
      final files =
          (search['files'] as List<dynamic>?) ?? const <dynamic>[];
      for (final filter in [...sources, ...files]) {
        if (filter == 'alle') continue;
        await _bumpAdditive(prefs, 'weight_filter_$filter', delta,
            _filterMin, _filterMax);
      }

      final empType =
          (search['employmentType'] as String?) ?? 'student';
      await _bumpAdditive(prefs, 'weight_employment_$empType', delta * 0.3,
          _modeMin, _modeMax);

      final query = (search['query'] as String?) ?? '';
      final language = (search['language'] as String?) ?? 'de';
      await _extractAndWeightKeywords(query, kwDelta, prefs, language);

      final url = (search['url'] as String?) ?? '';
      final host = _extractHost(url);
      if (host != null) {
        await _bumpAdditive(prefs, 'weight_domain_$host', delta,
            _domainMin, _domainMax);
      }

      // Coach-Choices lernen: Theme + Chip Gewichte
      final choices = search['coach_choices'];
      if (choices is List) {
        for (final c in choices) {
          if (c is! Map) continue;
          final theme = c['theme']?.toString();
          final dim = c['dim']?.toString();
          final chip = c['chip']?.toString();
          if (theme != null && theme.isNotEmpty) {
            await _bumpAdditive(prefs, 'weight_theme_$theme', delta * 0.5,
                _themeMin, _themeMax);
          }
          if (theme != null && dim != null && chip != null) {
            final chipKey = '${theme}__${dim}__$chip'
                .toLowerCase()
                .replaceAll(RegExp(r'[^a-z0-9_]'), '_');
            await _bumpAdditive(prefs, 'weight_chip_$chipKey', delta * 0.4,
                _chipMin, _chipMax);
          }
        }
      }

      fValue['applied'] = true;
      await feedbackBox.put(fk, fValue);
      processed++;
    }

    await _logPrivacyAction(
        'Interessen-Modell verfeinert ($processed Feedbacks).');

    if (kDebugMode) {
      debugPrint('Analyzer: applied $processed feedback events');
    }
  }

  Future<void> _applyDecay(SharedPreferences prefs) async {
    final keys =
        prefs.getKeys().where((k) => k.startsWith('weight_')).toList();
    int updated = 0;
    for (final k in keys) {
      final v = prefs.getDouble(k);
      if (v == null) continue;
      final next = v + (1.0 - v) * _decayFactor;
      if ((next - 1.0).abs() < 0.02) {
        await prefs.remove(k);
      } else {
        await prefs.setDouble(k, next);
      }
      updated++;
    }
    if (kDebugMode) {
      debugPrint('Weight decay applied to $updated keys.');
    }
  }

  Future<void> _bumpAdditive(SharedPreferences prefs, String key,
      double delta, double min, double max) async {
    final current = prefs.getDouble(key) ?? 1.0;
    final next = (current + delta).clamp(min, max);
    await prefs.setDouble(key, next);
  }

  Future<void> _logPrivacyAction(String message) async {
    if (!Hive.isBoxOpen(_logBoxName)) return;
    final logBox = Hive.box<dynamic>(_logBoxName);
    await logBox.add(<String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'action': 'interest_model_refinement',
      'message': message,
    });
    while (logBox.length > 50) {
      await logBox.deleteAt(0);
    }
  }

  Future<void> _rotateLog(Box<dynamic> box) async {
    while (box.length > _maxSearchLogEntries) {
      final oldestKey = box.keys.first;
      await box.delete(oldestKey);
    }
  }

  List<Map<String, dynamic>> getFeedbackForReview() {
    if (!Hive.isBoxOpen(_feedbackBoxName)) {
      return const <Map<String, dynamic>>[];
    }
    final box = Hive.box<dynamic>(_feedbackBoxName);
    return box.values
        .map((dynamic e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  
  /// Setzt initiale Keyword- und Filter-Gewichte basierend auf dem
  /// gewaehlten Beschaeftigungstyp aus dem Onboarding.
  ///
  /// Wird genau einmal am Ende des Onboarding-Wizards aufgerufen.
  /// Vorhandene Gewichte werden nur angehoben, nie abgesenkt —
  /// so dass spaetere Nutzungs-Signale immer Vorrang haben.
  ///
  /// Schluessel:
  ///   weight_kw_*             Keyword-Affinitaet   (1.2–1.6)
  ///   weight_filter_*         Quellen-Affinitaet   (1.3–1.7)
  ///   weight_mode_*           bevorzugter Modus    (1.2–1.4)
  ///   weight_employment_*     Beschaeftigungs-Bias (initial 1.3)
  Future<void> seedStarterWeights(String employmentType) async {
    final prefs = await SharedPreferences.getInstance();

    const starterWeights = <String, Map<String, double>>{
      'student': {
        'weight_kw_studie':           1.5,
        'weight_kw_studien':          1.5,
        'weight_kw_paper':            1.5,
        'weight_kw_forschung':        1.4,
        'weight_kw_wissenschaft':     1.4,
        'weight_kw_journal':          1.4,
        'weight_kw_thesis':           1.3,
        'weight_kw_literatur':        1.3,
        'weight_kw_erklaerung':       1.3,
        'weight_kw_loesung':          1.2,
        'weight_filter_academic':     1.6,
        'weight_filter_wikipedia':    1.4,
        'weight_filter_docs':         1.3,
        'weight_mode_precise':        1.4,
        'weight_mode_standard':       1.2,
      },
      'vollzeit': {
        // Spec: Effizienz-Jaeger — kein langes Lesen, aktuelle Infos, B2B
        'weight_kw_anleitung':        1.4,
        'weight_kw_howto':            1.4,
        'weight_kw_tool':             1.4,
        'weight_kw_software':         1.4,
        'weight_kw_workflow':         1.3,
        'weight_kw_produktiv':        1.3,
        'weight_kw_effizienz':        1.3,
        'weight_kw_vorlage':          1.2,
        'weight_kw_aktuell':          1.3, // intitle: + after: Aktualitaet
        'weight_filter_docs':         1.6,
        'weight_filter_foren':        1.4,
        'weight_filter_blogs':        1.3,
        // Gutefrage und Hobbyisten-Foren massiv abstrafen (Spec: Lärm)
        'weight_domain_gutefrage.net':     0.3,
        'weight_domain_wer-weiss-was.de':  0.3,
        'weight_domain_pinterest.com':     0.2,
        'weight_mode_precise':        1.5,
        'weight_mode_standard':       1.2,
      },
      'teilzeit': {
        // Spec: Balancierer / Familien-Manager — lokal + preisbewusst + echte Erfahrungen
        'weight_kw_tipps':            1.4,
        'weight_kw_ratgeber':         1.4,
        'weight_kw_erfahrungen':      1.5,
        'weight_kw_erfahrungsbericht':1.4,
        'weight_kw_bewertung':        1.4,
        'weight_kw_aktuell':          1.3,
        'weight_kw_vergleich':        1.3,
        'weight_kw_preis':            1.2,
        'weight_kw_guenstig':         1.2,
        'weight_filter_reddit':       1.6, // Community-Foren: echte Menschen
        'weight_filter_foren':        1.5,
        'weight_filter_news':         1.4,
        'weight_filter_offiziell':    1.3,
        // Content-Farmen abstrafen
        'weight_domain_gofeminin.de': 0.4,
        'weight_domain_desired.de':   0.4,
        'weight_domain_pinterest.com':0.3,
        'weight_mode_standard':       1.4,
        'weight_mode_discover':       1.3,
      },
      'rentner': {
        // Spec: Schutzwall gegen Scam, Trust-Domains fuer Medizin/Finanzen
        'weight_kw_einfach':          1.6,
        'weight_kw_erklaerung':       1.6,
        'weight_kw_schritt':          1.5,
        'weight_kw_anleitung':        1.5,
        'weight_kw_gesundheit':       1.5,
        'weight_kw_medikament':       1.4,
        'weight_kw_symptom':          1.4,
        'weight_kw_rente':            1.4,
        'weight_kw_pension':          1.3,
        // Trust-Domains (Medizin + Finanzen) stark aufwerten
        'weight_domain_stiftung-warentest.de': 1.8,
        'weight_domain_apotheken-umschau.de':  1.7,
        'weight_domain_bund.de':               1.7,
        'weight_domain_rki.de':                1.6,
        'weight_domain_bzga.de':               1.6,
        'weight_domain_verbraucherzentrale.de':1.6,
        // Scam-Domains und Social-Media-Lärm massiv abstrafen
        'weight_domain_pinterest.com':  0.2,
        'weight_domain_pinterest.de':   0.2,
        'weight_domain_tiktok.com':     0.2,
        'weight_domain_instagram.com':  0.3,
        'weight_filter_wikipedia':      1.7,
        'weight_filter_news':           1.5,
        'weight_filter_offiziell':      1.6,
        'weight_mode_standard':         1.5,
        'weight_mode_discover':         1.2,
      },
      'erwerbslos': {
        // Job-Suche (sanfte Vorgewichtung 1.08–1.12)
        'weight_kw_job':              1.12,
        'weight_kw_bewerbung':        1.12,
        'weight_kw_lebenslauf':       1.10,
        'weight_kw_vorlage':          1.10,
        'weight_kw_karriere':         1.08,
        // Antraege + staatliche Hilfen (Spec: offizielle Antraege + gute Foren)
        'weight_kw_foerderung':       1.10,
        'weight_kw_antrag':           1.10,
        'weight_kw_buergergeld':      1.10,
        'weight_kw_hartz':            1.08,
        'weight_kw_sozialleistung':   1.08,
        'weight_kw_wohngeld':         1.08,
        'weight_kw_hilfe':            1.08,
        // Behoerden aufwerten
        'weight_domain_arbeitsagentur.de':      1.12,
        'weight_domain_bmfsfj.de':              1.10,
        'weight_domain_gesetze-im-internet.de': 1.08,
        // Stellenboersen
        'weight_filter_stellenboersen': 1.12,
        'weight_filter_offiziell':    1.10,
        // Echte Hilfe-Foren
        'weight_filter_reddit':       1.08,
        'weight_filter_foren':        1.08,
        // Coaching-Scams abstrafen
        'weight_domain_geld-verdienen-sofort.de': 0.88,
        'weight_mode_standard':       1.06,
      },
    };

    final weights = starterWeights[employmentType] ?? {};
    for (final entry in weights.entries) {
      final current = prefs.getDouble(entry.key) ?? 0.0;
      if (entry.value > current) {
        await prefs.setDouble(entry.key, entry.value);
      }
    }

    // Leichte Vorgewichtung (1.1) — echtes Lernen passiert durch Chronik + Interessen
    final empKey = 'weight_employment_$employmentType';
    final currentEmp = prefs.getDouble(empKey) ?? 0.0;
    if (1.1 > currentEmp) {
      await prefs.setDouble(empKey, 1.1);
    }

    if (kDebugMode) {
      debugPrint(
        'seedStarterWeights: $employmentType — ${weights.length} Keys gesetzt.',
      );
    }
  }


  /// Setzt leichte Familienstatus-Starter-Gewichte.
  /// Wird zusammen mit seedStarterWeights am Ende des Onboardings aufgerufen.
  /// Werte bewusst gering (1.05–1.10) — Interessen + Chronik haben Vorrang.
  Future<void> seedStarterFamilyWeights(String familyStatus) async {
    final prefs = await SharedPreferences.getInstance();

    // Spec-konforme Familie-Profile (Werte bewusst gering 1.05–1.12,
    // Interessen + Chronik haben immer Vorrang).
    const familyWeights = <String, Map<String, double>>{
      // Baseline: nur berufliche Filter greifen, kein family overlay
      'single': {
        'weight_kw_freizeit':         1.06,
        'weight_kw_reise':            1.05,
        'weight_filter_blogs':        1.06,
        'weight_mode_discover':       1.06,
      },

      // Familie (mit Kindern): Schutz vor Pinterest + Mommy-Blog-Spam,
      // Trust-Domains fuer Gesundheit/Erziehung aufwerten
      'familie': {
        // Kinder-/Familien-Keywords
        'weight_kw_kinder':           1.10,
        'weight_kw_kindheit':         1.08,
        'weight_kw_schule':           1.08,
        'weight_kw_kita':             1.08,
        'weight_kw_erziehung':        1.10,
        'weight_kw_impfung':          1.08,
        'weight_kw_kinderarzt':       1.08,
        'weight_kw_kindergarten':     1.08,
        // Trust-Domains (medizinisch + erzieherisch)
        'weight_domain_kindergesundheit-info.de': 1.12,
        'weight_domain_familienportal.de':        1.12,
        'weight_domain_stiftung-warentest.de':    1.10,
        'weight_domain_bzga.de':                  1.10,
        'weight_domain_bund.de':                  1.08,
        // Mommy-Blog-SEO-Spam + Pinterest abstrafen
        'weight_domain_pinterest.com':  0.88,
        'weight_domain_pinterest.de':   0.88,
        'weight_domain_desired.de':     0.88,
        'weight_domain_gofeminin.de':   0.88,
        'weight_domain_mamaclub.de':    0.88,
        'weight_filter_offiziell':      1.10,
        'weight_mode_standard':         1.06,
      },

      // Alleinerziehend: Effizienz + staatliche Hilfen + echte Foren,
      // Scam-Anwalts-Portale und toxische Foren raus
      'alleinerziehend': {
        // Hilfe + Recht + Foerderung stark vorgewichten
        'weight_kw_foerderung':       1.12,
        'weight_kw_unterstuetzung':   1.12,
        'weight_kw_recht':            1.10,
        'weight_kw_unterhalt':        1.10,
        'weight_kw_sorgerecht':       1.10,
        'weight_kw_antrag':           1.10,
        'weight_kw_beratung':         1.08,
        'weight_kw_kostenlos':        1.10,
        'weight_kw_kinder':           1.08,
        // Staatliche Seiten stark aufwerten (Spec: maximale Effizienz)
        'weight_domain_bmfsfj.de':           1.15,
        'weight_domain_arbeitsagentur.de':   1.12,
        'weight_domain_bundesregierung.de':  1.10,
        'weight_domain_bund.de':             1.10,
        'weight_domain_vamv.de':             1.10, // Verband alleinerziehender Muetter
        // Echte Foren/Reddit-Communities aufwerten
        'weight_filter_reddit':       1.12,
        'weight_filter_foren':        1.08,
        // Scam-Anwalts-Portale abstrafen (Spec)
        'weight_domain_anwalt.de':    0.88,
        'weight_domain_anwalt24.de':  0.85,
        'weight_domain_pinterest.com':0.88,
        'weight_filter_offiziell':    1.12,
        'weight_mode_standard':       1.06,
      },
    };

    final weights = familyWeights[familyStatus] ?? {};
    for (final entry in weights.entries) {
      final current = prefs.getDouble(entry.key) ?? 0.0;
      if (entry.value > current) {
        await prefs.setDouble(entry.key, entry.value);
      }
    }

    if (kDebugMode) {
      debugPrint(
        'seedStarterFamilyWeights: $familyStatus — ${weights.length} Keys gesetzt.',
      );
    }
  }

  Future<void> clearAllFeedback() async {
    if (!Hive.isBoxOpen(_feedbackBoxName)) return;
    await Hive.box<dynamic>(_feedbackBoxName).clear();
  }

  Future<void> _extractAndWeightKeywords(String query, double delta,
      SharedPreferences prefs, String language) async {
    final clean = query
        .replaceAll(
            RegExp(
                r'\b(site|inurl|intitle|intext|filetype|ext|before|after|allintitle|allintext|allinurl):\S+'),
            ' ')
        .replaceAll(RegExp(r'-\S+'), ' ')
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .toLowerCase();

    final stopwords = stopwordsForLanguage(language);
    final words = clean
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 3 && !stopwords.contains(w))
        .toSet()
        .toList();

    for (final word in words) {
      await _bumpAdditive(
          prefs, 'weight_kw_$word', delta, _kwMin, _kwMax);
    }
    if (kDebugMode) {
      debugPrint('Updated keyword weights: ${words.length} terms');
    }
  }

  String? _extractHost(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.replaceFirst(RegExp(r'^www\.'), '');
      const searchEngines = {
        'google.com', 'google.de', 'bing.com', 'duckduckgo.com',
        'startpage.com', 'search.brave.com',
      };
      if (searchEngines.contains(host)) return null;
      return host.isEmpty ? null : host;
    } catch (_) {
      return null;
    }
  }
}
