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
      'familyStatus':
          (settings['familyStatus'] as String?) ?? 'single',
      if ((settings['interests'] as List?)?.isNotEmpty == true)
        'interests': (settings['interests'] as List)
            .whereType<String>()
            .toList(),
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

    // Sofortige Verarbeitung — kein 7-Tage-Warten.
    // SharedPreferences laden und Gewichte direkt aktualisieren.
    try {
      final prefs = await SharedPreferences.getInstance();
      await _applyPendingFeedbacks(prefs);
    } catch (e) {
      if (kDebugMode) debugPrint('Sofort-Feedback-Apply fehlgeschlagen: $e');
    }
  }

  /// Wöchentliches Maintenance-Fenster.
  ///
  /// Feedback wird seit v4 sofort in [trackFeedback] verarbeitet.
  /// [checkAndAnalyze] übernimmt jetzt zwei Aufgaben:
  ///   1) Decay: alle weight_*-Werte sanft Richtung 1.0 ziehen (wöchentlich).
  ///   2) Safety-Net: verbleibende unangewendete Feedbacks nachholen,
  ///      die z.B. durch App-Absturz noch nicht verarbeitet wurden.
  /// Setzt alle Lern-Gewichte (weight_*-Keys in SharedPreferences) zurueck.
  ///
  /// Stammdaten (Hive-Vault), Suchlogs und Token-Tracking bleiben vollstaendig
  /// erhalten — nur die adaptiven Gewichte werden auf Basis-1.0 zurueckgesetzt.
  /// Nuetzlich wenn der User einen "Neustart" ohne Datenverlust moechte.
  Future<void> resetLearningWeights() async {
    final prefs = await SharedPreferences.getInstance();
    final toRemove =
        prefs.getKeys().where((k) => k.startsWith('weight_')).toList();
    for (final k in toRemove) {
      await prefs.remove(k);
    }
    if (kDebugMode) {
      debugPrint('resetLearningWeights: ${toRemove.length} Gewichts-Keys entfernt.');
    }
  }

  Future<void> checkAndAnalyze() async {
    final prefs = await SharedPreferences.getInstance();
    final lastAnalysis = prefs.getInt('last_analysis') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    const weekMs = 7 * 24 * 60 * 60 * 1000;
    if (now - lastAnalysis > weekMs) {
      // Safety-Net: orphaned Feedbacks aufholen
      await _applyPendingFeedbacks(prefs);
      // Decay nur wöchentlich — nicht bei jedem App-Start
      await _applyDecay(prefs);
      await prefs.setInt('last_analysis', now);
    }
  }

  Future<void> _applyPendingFeedbacks(SharedPreferences prefs) async {
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

      final familyStatus =
          (search['familyStatus'] as String?) ?? 'single';
      if (familyStatus != 'single') {
        await _bumpAdditive(prefs, 'weight_family_$familyStatus',
            delta * 0.2, _modeMin, _modeMax);
      }

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
        'Gewichte sofort angewendet ($processed Feedbacks).');

    if (kDebugMode) {
      if (kDebugMode) debugPrint('_applyPendingFeedbacks: $processed Feedbacks sofort verarbeitet');
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
      if (kDebugMode) debugPrint('Weight decay applied to $updated keys.');
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
      if (kDebugMode) debugPrint(
        'seedStarterWeights: $employmentType — ${weights.length} Keys gesetzt.',
      );
    }
  }


  /// Setzt leichte Familienstatus-Starter-Gewichte.
  /// Wird zusammen mit seedStarterWeights am Ende des Onboardings aufgerufen.
  /// Werte bewusst gering (1.05–1.10) — Interessen + Chronik haben Vorrang.
  Future<void> seedStarterFamilyWeights(String familyStatus) async {
    final prefs = await SharedPreferences.getInstance();

    // Nur einmal ausfuehren, damit Chronik-Import die Starter-Werte
    // spaeter nicht ueberschreibt.
    if (prefs.getBool("hasSeededFamilyWeights") == true) return;
    await prefs.setBool("hasSeededFamilyWeights", true);
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

    // Initial family-status weight — analog zu employment weight (1.1 Startwert).
    // Wird durch trackFeedback / _applyPendingFeedbacks kontinuierlich verfeinert.
    //   < 0.7  : neg. Feedback dominiert → Overlay wird gedaempft
    //   0.7–1.1: neutral / Standard-Overlay
    //   >= 1.2 : positives Signal → erweitertes Overlay (mehr Trust-Domains)
    //   >= 1.4 : starkes Signal  → zusaetzliche SoftTerms injiziert
    final famKey = 'weight_family_' + familyStatus;
    final currentFam = prefs.getDouble(famKey) ?? 0.0;
    if (1.1 > currentFam) {
      await prefs.setDouble(famKey, 1.1);
    }

    if (kDebugMode) {
      if (kDebugMode) debugPrint(
        'seedStarterFamilyWeights: $familyStatus — ${weights.length} Keys gesetzt.',
      );
    }
  }

  /// Setzt kategorie-semantische Filter/Modus-Gewichte basierend auf
  /// ausgewaehlten Interessen. Ergaenzt [ChromeImportService.applyInterestBumps]
  /// (Token-Ebene) um Quellen-Filter-, Modus- und Domain-Boosts auf Kategorie-Ebene.
  /// Bewusst statisch und mild (0.06–0.12) — echtes Lernen passiert per Chronik.
  ///
  /// Aufruf: bei Onboarding-Abschluss + jedes Mal wenn neue Interessen gesetzt werden.
  static Future<void> applyInterestCategoryWeights(List<String> paths) async {
    if (paths.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();

    // Top-Kategorie aus Pfad-Prefix extrahieren (z.B. "musik/rap/sido" -> "musik")
    final categories = paths.map((p) => p.split('/').first).toSet();

    // Kategorie -> semantische Filter/Modus-Gewichte (spec-aligned, sanft)
    const categoryMap = <String, Map<String, double>>{
      'musik':        { 'weight_filter_blogs': 0.08, 'weight_filter_foren': 0.06,        'weight_mode_discover': 0.08 },
      'sport':        { 'weight_filter_news':  0.10, 'weight_filter_blogs': 0.06,        'weight_mode_standard': 0.06 },
      'wissenschaft': { 'weight_filter_academic': 0.12, 'weight_filter_wikipedia': 0.08, 'weight_mode_precise': 0.10 },
      'mathe':        { 'weight_filter_academic': 0.10, 'weight_filter_docs': 0.08,      'weight_mode_precise': 0.10 },
      'tech':         { 'weight_filter_docs': 0.12, 'weight_filter_foren': 0.08,         'weight_mode_precise': 0.08 },
      'gaming':       { 'weight_filter_foren': 0.10, 'weight_filter_blogs': 0.06,        'weight_mode_discover': 0.06 },
      'film':         { 'weight_filter_blogs': 0.08, 'weight_filter_reddit': 0.08,       'weight_mode_discover': 0.08 },
      'kochen':       { 'weight_filter_blogs': 0.10,                                     'weight_mode_discover': 0.08 },
      'reisen':       { 'weight_filter_blogs': 0.08, 'weight_filter_reddit': 0.06,       'weight_mode_discover': 0.10 },
      'sprachen':     { 'weight_filter_docs': 0.08, 'weight_filter_wikipedia': 0.08,     'weight_mode_standard': 0.06 },
      'garten':       { 'weight_filter_blogs': 0.10,                                     'weight_mode_discover': 0.06 },
      'auto':         { 'weight_filter_foren': 0.10, 'weight_filter_blogs': 0.06,        'weight_mode_standard': 0.06 },
    };

    for (final cat in categories) {
      final boosts = categoryMap[cat];
      if (boosts == null) continue;
      for (final entry in boosts.entries) {
        final cur = prefs.getDouble(entry.key) ?? 1.0;
        final next = (cur + entry.value).clamp(0.2, 4.0);
        await prefs.setDouble(entry.key, next);
      }
    }

    if (kDebugMode) {
      if (kDebugMode) debugPrint('applyInterestCategoryWeights: ' + categories.join(', ') + ' — ' + categories.length.toString() + ' Kategorie-Boosts gesetzt.');
    }
  }

  Future<void> clearAllFeedback() async {
    if (!Hive.isBoxOpen(_feedbackBoxName)) return;
    await Hive.box<dynamic>(_feedbackBoxName).clear();
  }


  /// Setzt sofortige Starter-Gewichte fuer spezifische Interesse-Items.
  ///
  /// Wird aufgerufen wenn der User neue Interessen hinzufuegt (added-Liste).
  /// Jedes bekannte Item-Path wird einer Menge von weight_kw_* / weight_domain_*
  /// zugeordnet und sofort in SharedPreferences gesetzt.
  ///
  /// Regeln:
  ///   • Nur angehoben, nie abgesenkt (vorhandene Lern-Gewichte haben Vorrang)
  ///   • Werte: kw_* 1.20–1.35, domain_* 1.25–1.40 (unter Employment-Seed-Werten)
  ///   • Unbekannte Paths werden ignoriert — kein Fehler
  static Future<void> seedInterestItemWeights(List<String> paths) async {
    final prefs = await SharedPreferences.getInstance();

    // ── Item-Gewichts-Map ──────────────────────────────────────────────────
    // Format: 'top/sub/item' → { 'weight_kw_X': value, 'weight_domain_Y': value }
    const itemWeights = <String, Map<String, double>>{
      // ── Finanzen / Haushalt & Sparen ──
      'finanzen/haushalt/budgetplan': {
        'weight_kw_haushalt':    1.28,
        'weight_kw_budgetplan':  1.30,
        'weight_kw_sparen':      1.25,
        'weight_kw_ausgaben':    1.22,
      },
      'finanzen/haushalt/strom': {
        'weight_kw_strom':       1.28,
        'weight_kw_energie':     1.25,
        'weight_kw_tarif':       1.22,
        'weight_kw_vergleich':   1.20,
        'weight_domain_verivox.de': 1.30,
        'weight_domain_check24.de': 1.28,
      },
      'finanzen/haushalt/lebensmittel': {
        'weight_kw_lebensmittel': 1.25,
        'weight_kw_guenstig':    1.28,
        'weight_kw_supermarkt':  1.22,
        'weight_kw_angebot':     1.20,
      },
      'finanzen/haushalt/rabattcodes': {
        'weight_kw_rabatt':      1.28,
        'weight_kw_coupon':      1.28,
        'weight_kw_gutschein':   1.25,
        'weight_domain_gutscheinpony.de': 1.25,
      },
      'finanzen/haushalt/secondhand': {
        'weight_kw_secondhand':  1.28,
        'weight_kw_gebraucht':   1.25,
        'weight_domain_kleinanzeigen.de': 1.35,
        'weight_domain_vinted.de': 1.30,
      },

      // ── Finanzen / Sozialleistungen ──
      'finanzen/soziales/buergergeld': {
        'weight_kw_buergergeld':    1.35,
        'weight_kw_sozialleistung': 1.28,
        'weight_kw_antrag':         1.28,
        'weight_kw_foerderung':     1.25,
        'weight_domain_arbeitsagentur.de':       1.40,
        'weight_domain_bund.de':                 1.35,
        'weight_domain_gesetze-im-internet.de':  1.30,
      },
      'finanzen/soziales/kindergeld': {
        'weight_kw_kindergeld':     1.35,
        'weight_kw_kinderzuschlag': 1.30,
        'weight_kw_antrag':         1.25,
        'weight_domain_familienkasse.de': 1.40,
        'weight_domain_bund.de':          1.30,
      },
      'finanzen/soziales/wohngeld': {
        'weight_kw_wohngeld':    1.35,
        'weight_kw_antrag':      1.25,
        'weight_kw_miete':       1.22,
        'weight_domain_bund.de': 1.35,
      },
      'finanzen/soziales/bafoegsoz': {
        'weight_kw_bafoeg':      1.35,
        'weight_kw_foerderung':  1.28,
        'weight_kw_antrag':      1.25,
        'weight_domain_bafoeg.de': 1.40,
        'weight_domain_bund.de':   1.30,
      },
      'finanzen/soziales/grundsicherung': {
        'weight_kw_grundsicherung': 1.35,
        'weight_kw_rente':          1.28,
        'weight_kw_alter':          1.22,
        'weight_domain_bund.de':    1.35,
        'weight_domain_deutsche-rentenversicherung.de': 1.35,
      },
      'finanzen/soziales/sozialticket': {
        'weight_kw_sozialticket':   1.30,
        'weight_kw_ermaessigung':   1.28,
        'weight_kw_ticket':         1.22,
        'weight_kw_oeffentlich':    1.20,
      },

      // ── Finanzen / Steuern ──
      'finanzen/steuern/steuererklaerung': {
        'weight_kw_steuererklaerung': 1.35,
        'weight_kw_steuern':          1.28,
        'weight_kw_finanzamt':        1.25,
        'weight_domain_elster.de':    1.40,
        'weight_domain_lohnsteuer-kompakt.de': 1.30,
      },
      'finanzen/steuern/werbungskosten': {
        'weight_kw_werbungskosten': 1.32,
        'weight_kw_absetzbar':      1.28,
        'weight_kw_steuertipp':     1.25,
        'weight_domain_lohnsteuer-kompakt.de': 1.30,
      },
      'finanzen/steuern/elster': {
        'weight_kw_elster':         1.32,
        'weight_kw_steuerportal':   1.25,
        'weight_domain_elster.de':  1.40,
      },
      'finanzen/steuern/minijob': {
        'weight_kw_minijob':             1.32,
        'weight_kw_steuerpflicht':       1.28,
        'weight_domain_minijob-zentrale.de': 1.38,
      },
      'finanzen/steuern/gewerbeanmeldung': {
        'weight_kw_gewerbe':         1.30,
        'weight_kw_umsatzsteuer':    1.28,
        'weight_kw_selbststaendig':  1.25,
        'weight_domain_ihk.de':      1.30,
      },

      // ── Finanzen / Investieren ──
      'finanzen/investieren/etf': {
        'weight_kw_etf':          1.32,
        'weight_kw_indexfonds':   1.30,
        'weight_kw_sparplan':     1.28,
        'weight_kw_geldanlage':   1.25,
        'weight_domain_justetf.com':       1.38,
        'weight_domain_finanztip.de':      1.35,
        'weight_domain_extraetf.com':      1.30,
      },
      'finanzen/investieren/aktien': {
        'weight_kw_aktien':       1.30,
        'weight_kw_dividende':    1.28,
        'weight_kw_boerse':       1.25,
        'weight_domain_onvista.de':   1.35,
        'weight_domain_finanzen.net': 1.30,
      },
      'finanzen/investieren/immobilien': {
        'weight_kw_immobilien':   1.30,
        'weight_kw_kapitalanlage':1.28,
        'weight_kw_rendite':      1.25,
        'weight_domain_immobilienscout24.de': 1.32,
      },
      'finanzen/investieren/krypto': {
        'weight_kw_krypto':       1.28,
        'weight_kw_bitcoin':      1.25,
        'weight_kw_blockchain':   1.22,
        'weight_domain_coinmarketcap.com': 1.30,
      },

      // ── Finanzen / Mietrecht ──
      'finanzen/mietrecht/mietvertrag': {
        'weight_kw_mietvertrag':  1.32,
        'weight_kw_kuendigung':   1.28,
        'weight_kw_mietrecht':    1.25,
        'weight_domain_mieterbund.de':       1.38,
        'weight_domain_verbraucherzentrale.de': 1.30,
      },
      'finanzen/mietrecht/nebenkosten': {
        'weight_kw_nebenkosten':  1.32,
        'weight_kw_betriebskosten':1.28,
        'weight_domain_mieterbund.de': 1.35,
      },
      'finanzen/mietrecht/mietpreisbremse': {
        'weight_kw_mietpreisbremse': 1.30,
        'weight_kw_mietspiegel':     1.28,
        'weight_domain_mieterbund.de': 1.35,
      },
      'finanzen/mietrecht/vermieter': {
        'weight_kw_vermieter':    1.28,
        'weight_kw_rechte':       1.25,
        'weight_kw_mietrecht':    1.25,
        'weight_domain_mieterbund.de': 1.35,
      },

      // ── Finanzen / Familienrecht ──
      'finanzen/familienrecht/unterhalt': {
        'weight_kw_unterhalt':          1.35,
        'weight_kw_unterhaltsrechner':  1.30,
        'weight_kw_duesseldorfer':      1.25,
        'weight_domain_bmj.de':         1.35,
        'weight_domain_gesetze-im-internet.de': 1.28,
      },
      'finanzen/familienrecht/sorgerecht': {
        'weight_kw_sorgerecht':   1.35,
        'weight_kw_umgangsrecht': 1.30,
        'weight_kw_familiengericht': 1.25,
        'weight_domain_bmj.de':   1.35,
      },
      'finanzen/familienrecht/scheidung': {
        'weight_kw_scheidung':    1.35,
        'weight_kw_trennung':     1.28,
        'weight_kw_zugewinn':     1.25,
        'weight_domain_bmj.de':   1.35,
      },
      'finanzen/familienrecht/erbrecht': {
        'weight_kw_erbrecht':     1.32,
        'weight_kw_testament':    1.30,
        'weight_kw_erbe':         1.28,
        'weight_domain_bmj.de':   1.35,
      },

      // ── Finanzen / Rente ──
      'finanzen/rente/gesetzlichrente': {
        'weight_kw_rente':        1.32,
        'weight_kw_renteninfo':   1.30,
        'weight_kw_rentenpunkt':  1.28,
        'weight_domain_deutsche-rentenversicherung.de': 1.40,
        'weight_domain_bund.de':  1.30,
      },
      'finanzen/rente/riester': {
        'weight_kw_riester':      1.32,
        'weight_kw_ruerup':       1.28,
        'weight_kw_foerderung':   1.25,
        'weight_domain_finanztip.de': 1.35,
      },
      'finanzen/rente/betriebsrente': {
        'weight_kw_betriebsrente':  1.30,
        'weight_kw_entgeltumwandlung': 1.28,
        'weight_domain_finanztip.de': 1.32,
      },
      'finanzen/rente/fruehverrentung': {
        'weight_kw_fruehverrentung': 1.30,
        'weight_kw_renteneintritt':  1.28,
        'weight_kw_rentenalter':     1.25,
        'weight_domain_deutsche-rentenversicherung.de': 1.38,
      },

      // ── Bildung / Bewerbung ──
      'bildung/bewerbung/lebenslauf': {
        'weight_kw_lebenslauf':   1.32,
        'weight_kw_vorlage':      1.28,
        'weight_kw_cv':           1.25,
        'weight_kw_bewerbung':    1.25,
        'weight_domain_lebenslauf.de': 1.30,
      },
      'bildung/bewerbung/anschreiben': {
        'weight_kw_anschreiben':  1.32,
        'weight_kw_bewerbung':    1.28,
        'weight_kw_vorlage':      1.25,
      },
      'bildung/bewerbung/linkedinprofil': {
        'weight_kw_linkedin':     1.30,
        'weight_kw_profil':       1.25,
        'weight_kw_netzwerk':     1.22,
        'weight_domain_linkedin.com': 1.35,
      },
      'bildung/bewerbung/vorstellungsgespraech': {
        'weight_kw_vorstellungsgesprach': 1.32,
        'weight_kw_interview':            1.28,
        'weight_kw_fragen':               1.22,
      },
      'bildung/bewerbung/gehaltsverhandlung': {
        'weight_kw_gehalt':            1.30,
        'weight_kw_gehaltsverhandlung':1.32,
        'weight_kw_verhandlung':       1.25,
        'weight_domain_stepstone.de':  1.28,
      },
      'bildung/bewerbung/quereinstieg': {
        'weight_kw_quereinstieg': 1.32,
        'weight_kw_umschulung':   1.28,
        'weight_kw_umorientierung':1.25,
        'weight_domain_arbeitsagentur.de': 1.35,
      },

      // ── Bildung / Studium ──
      'bildung/studium/hochschulbewerbung': {
        'weight_kw_hochschule':   1.30,
        'weight_kw_nc':           1.28,
        'weight_kw_zulassung':    1.28,
        'weight_kw_studiengang':  1.25,
        'weight_domain_hochschulstart.de': 1.35,
        'weight_domain_anabin.kmk.org':   1.28,
      },
      'bildung/studium/bafoegstudy': {
        'weight_kw_bafoeg':        1.35,
        'weight_kw_foerderung':    1.28,
        'weight_domain_bafoeg.de': 1.40,
        'weight_domain_bund.de':   1.28,
      },
      'bildung/studium/lerntechniken': {
        'weight_kw_lernmethode':  1.28,
        'weight_kw_pruefung':     1.28,
        'weight_kw_vorbereitung': 1.25,
        'weight_kw_pomodoro':     1.22,
      },
      'bildung/studium/auslandsstudium': {
        'weight_kw_auslandsstudium': 1.30,
        'weight_kw_erasmus':         1.30,
        'weight_kw_ausland':         1.25,
        'weight_domain_daad.de':     1.38,
      },
      'bildung/studium/berufsausbildung': {
        'weight_kw_ausbildung':      1.30,
        'weight_kw_berufsausbildung':1.30,
        'weight_kw_azubi':           1.25,
        'weight_domain_ausbildung.de': 1.32,
      },

      // ── Bildung / Weiterbildung ──
      'bildung/weiterbildung/onlinekurse': {
        'weight_kw_onlinekurs':   1.30,
        'weight_kw_kurs':         1.25,
        'weight_domain_udemy.com':    1.35,
        'weight_domain_coursera.org': 1.35,
        'weight_domain_edx.org':      1.28,
      },
      'bildung/weiterbildung/zertifikate': {
        'weight_kw_zertifikat':   1.30,
        'weight_kw_aws':          1.28,
        'weight_kw_azure':        1.28,
        'weight_kw_comptia':      1.25,
        'weight_domain_aws.amazon.com':   1.30,
        'weight_domain_microsoft.com':    1.28,
      },
      'bildung/weiterbildung/umschulung': {
        'weight_kw_umschulung':   1.35,
        'weight_kw_foerderung':   1.28,
        'weight_kw_bildungsgutschein': 1.30,
        'weight_domain_arbeitsagentur.de': 1.40,
      },
      'bildung/weiterbildung/sprachkurse': {
        'weight_kw_sprachkurs':   1.28,
        'weight_kw_vhs':          1.25,
        'weight_domain_goethe.de':    1.35,
        'weight_domain_vhs.de':       1.30,
      },
      'bildung/weiterbildung/coaching': {
        'weight_kw_coaching':     1.25,
        'weight_kw_mentaltraining':1.22,
        'weight_kw_karriere':     1.22,
      },

      // ── Bildung / Selbststaendigkeit ──
      'bildung/selbststaendig/gruendung': {
        'weight_kw_gruendung':    1.30,
        'weight_kw_startup':      1.25,
        'weight_kw_unternehmen':  1.22,
        'weight_domain_gruenderplattform.de': 1.38,
        'weight_domain_ihk.de':             1.30,
      },
      'bildung/selbststaendig/freelance': {
        'weight_kw_freelance':     1.32,
        'weight_kw_freiberuflich': 1.28,
        'weight_kw_auftraege':     1.25,
        'weight_domain_gulp.de':      1.28,
        'weight_domain_freelance.de': 1.28,
      },
      'bildung/selbststaendig/businessplan': {
        'weight_kw_businessplan': 1.30,
        'weight_kw_geschaeftsplan':1.28,
        'weight_kw_vorlage':      1.22,
        'weight_domain_gruenderplattform.de': 1.35,
      },
      'bildung/selbststaendig/foerdermittel': {
        'weight_kw_foerdermittel':    1.32,
        'weight_kw_gruenderzuschuss': 1.30,
        'weight_kw_foerderung':       1.28,
        'weight_domain_arbeitsagentur.de': 1.35,
        'weight_domain_bund.de':           1.28,
      },

      // ── Bildung / Kinder ──
      'bildung/kinder/hausaufgaben': {
        'weight_kw_hausaufgaben': 1.28,
        'weight_kw_schule':       1.25,
        'weight_kw_erklaerung':   1.22,
        'weight_domain_sofatutor.com':  1.30,
        'weight_domain_studysmarter.de':1.28,
      },
      'bildung/kinder/nachhilfe': {
        'weight_kw_nachhilfe':    1.30,
        'weight_kw_foerderunterricht':1.28,
        'weight_domain_sofatutor.com':    1.32,
        'weight_domain_schuelerhilfe.de': 1.30,
      },
      'bildung/kinder/schulwahl': {
        'weight_kw_schulsystem':  1.28,
        'weight_kw_schulwahl':    1.28,
        'weight_kw_gymnasium':    1.22,
        'weight_domain_bildungsserver.de': 1.30,
      },
      'bildung/kinder/lernspiele': {
        'weight_kw_lernspiel':    1.28,
        'weight_kw_kinder':       1.22,
        'weight_kw_app':          1.20,
        'weight_domain_anton.app':      1.32,
        'weight_domain_schlaukopf.de':  1.28,
      },
      'bildung/kinder/kitaschule': {
        'weight_kw_kita':         1.30,
        'weight_kw_kitaplatz':    1.30,
        'weight_kw_schulanmeldung':1.28,
        'weight_kw_einschulung':  1.25,
        'weight_domain_familienportal.de': 1.35,
      },

      // ── Sport (hochspezifische Items) ──
      'sport/fitness/krafttraining': {
        'weight_kw_krafttraining': 1.28,
        'weight_kw_muskelaufbau':  1.25,
        'weight_kw_trainingsplan': 1.25,
        'weight_domain_muskelaufbau.com': 1.28,
      },
      'sport/fitness/yoga': {
        'weight_kw_yoga':         1.28,
        'weight_kw_asana':        1.22,
        'weight_kw_meditation':   1.22,
        'weight_domain_yogaeasy.de': 1.30,
      },
      'sport/fitness/altersgerecht': {
        'weight_kw_seniorensport': 1.28,
        'weight_kw_gelenkschonend':1.28,
        'weight_kw_bewegung':      1.22,
      },
      'sport/fitness/reha': {
        'weight_kw_physiotherapie':1.30,
        'weight_kw_rehasport':     1.30,
        'weight_kw_uebungen':      1.22,
        'weight_domain_apotheken-umschau.de': 1.30,
      },

      // ── Kochen (hochspezifische Items) ──
      'kochen/gesund/mealprep': {
        'weight_kw_mealprep':     1.28,
        'weight_kw_vorbereitung': 1.22,
        'weight_kw_gesund':       1.22,
        'weight_kw_rezept':       1.20,
      },
      'kochen/familie/guenstigkochen': {
        'weight_kw_guenstig':     1.28,
        'weight_kw_billig':       1.25,
        'weight_kw_haushalt':     1.22,
        'weight_kw_rezept':       1.20,
      },
      'kochen/seniorenkueche/herzgesund': {
        'weight_kw_herzgesund':   1.28,
        'weight_kw_ernaehrung':   1.25,
        'weight_kw_cholesterin':  1.22,
        'weight_domain_apotheken-umschau.de': 1.32,
      },
    };

    // ── Gewichte setzen (nie absenken) ───────────────────────────────────
    int updated = 0;
    for (final path in paths) {
      final weights = itemWeights[path];
      if (weights == null) continue;
      for (final entry in weights.entries) {
        final current = prefs.getDouble(entry.key) ?? 0.0;
        if (entry.value > current) {
          await prefs.setDouble(entry.key, entry.value);
          updated++;
        }
      }
    }
    if (kDebugMode) {
      if (kDebugMode) debugPrint(
        'seedInterestItemWeights: ${paths.length} Paths → $updated Keys gesetzt.',
      );
    }
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
      if (kDebugMode) debugPrint('Updated keyword weights: ${words.length} terms');
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
