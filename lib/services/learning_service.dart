import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LearningService {
  static const String _boxName = 'learning_data'; // Raw History
  static const String _logBoxName = 'learning_log'; // Audit Trail
  static const String _feedbackBoxName = 'learning_feedback'; // Raw Feedbacks

  Future<void> init() async {
    await Hive.openBox(_boxName);
    await Hive.openBox(_logBoxName);
    await Hive.openBox(_feedbackBoxName);
  }

  // LERN-DATEN (Verlauf): Dient nur der wöchentlichen Analyse
  Future<void> trackSearch({
    required String query,
    required String url,
    required Map<String, dynamic> settings,
    required List<String> sources,
    required List<String> files,
    required String mode,
  }) async {
    final box = Hive.box(_boxName);
    final key = DateTime.now().millisecondsSinceEpoch.toString();
    await box.put(key, {
      'query': query,
      'url': url,
      'timestamp': DateTime.now().toIso8601String(),
      'sources': sources,
      'files': files,
      'mode': mode,
    });
  }

  // FEEDBACK: Qualitative Daten für das Interessen-Modell
  Future<void> trackFeedback(String rating, {String? comment}) async {
    final box = Hive.box(_feedbackBoxName);
    final searchBox = Hive.box(_boxName);

    String? lastSearchId;
    if (searchBox.isNotEmpty) {
      lastSearchId = searchBox.keys.last.toString();
    }

    final key = DateTime.now().millisecondsSinceEpoch.toString();
    await box.put(key, {
      'search_id': lastSearchId,
      'rating': rating,
      'comment': comment ?? '',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<void> checkAndAnalyze() async {
    final prefs = await SharedPreferences.getInstance();
    final lastAnalysis = prefs.getInt('last_analysis') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (now - lastAnalysis > 7 * 24 * 60 * 60 * 1000) {
      await _analyzeAndOptimize();
      await prefs.setInt('last_analysis', now);
    }
  }

  Future<void> _analyzeAndOptimize() async {
    final searchBox = Hive.box(_boxName);
    final feedbackBox = Hive.box(_feedbackBoxName);
    final logBox = Hive.box(_logBoxName);

    final searchData = searchBox.toMap();
    final feedbackData = feedbackBox.toMap();
    final prefs = await SharedPreferences.getInstance();

    // 1. LERNEN & SPEZIALISIEREN (Modell-Aufbau)
    // Wir verändern hier die Gewichte in den SharedPreferences.
    // Diese bleiben dauerhaft erhalten und bilden das "Interessen-Modell".
    feedbackData.forEach((fKey, fValue) {
      final searchId = fValue['search_id'];
      final rating = fValue['rating'];
      final multiplier = (rating == 'up') ? 1.1 : 0.85;

      if (searchId != null && searchData.containsKey(searchId)) {
        final search = searchData[searchId];

        // Modus-Interesse schärfen
        final mode = search['mode'] as String;
        double currentModeWeight = prefs.getDouble('weight_mode_$mode') ?? 1.0;
        prefs.setDouble('weight_mode_$mode', (currentModeWeight * multiplier).clamp(0.1, 5.0));

        // Filter-Interesse schärfen
        final sources = search['sources'] as List;
        final files = search['files'] as List;
        for (var filter in [...sources, ...files]) {
          double currentFilterWeight = prefs.getDouble('weight_filter_$filter') ?? 1.0;
          prefs.setDouble('weight_filter_$filter', (currentFilterWeight * multiplier).clamp(0.1, 5.0));
        }
      }
    });

    // 2. ANONYMISIERTER FEEDBACK-EXPORT (Nur bei Einwilligung)
    // Dieses Feedback ist für den Entwickler, um die App an sich zu verbessern.
    // Es enthält KEIN Interessen-Modell und KEINE Gewichte.
    final List<Map<String, dynamic>> anonymousFeedbackExport = [];
    if (prefs.getBool('allowFeedback') ?? false) {
      feedbackData.forEach((fKey, fValue) {
        anonymousFeedbackExport.add({
          'rating': fValue['rating'],
          'comment': fValue['comment'],
          'timestamp': fValue['timestamp'],
        });
      });
    }

    if (anonymousFeedbackExport.isNotEmpty) {
      await logBox.put('feedback_export_${DateTime.now().millisecondsSinceEpoch}', anonymousFeedbackExport);
    }

    // 3. RADIKALE LÖSCHUNG DER ROHDATEN (Privacy Hygiene)
    // Wir löschen ALLES, was Rückschlüsse auf das Verhalten zulässt.
    // Das Ergebnis des Lernens (die Gewichte) bleibt erhalten.
    await searchBox.clear();
    await feedbackBox.clear();

    await _logPrivacyAction('Interessen-Modell verfeinert. Verlaufs-Hygiene durchgeführt. Gewichte sind persistent.');
  }

  Future<void> _logPrivacyAction(String message) async {
    final logBox = Hive.box(_logBoxName);
    await logBox.add({
      'timestamp': DateTime.now().toIso8601String(),
      'action': 'interest_model_refinement',
      'message': message,
    });
  }
}
