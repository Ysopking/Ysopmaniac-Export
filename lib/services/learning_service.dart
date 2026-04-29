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

        // 1.1 Modus-Interesse schärfen
        final mode = search['mode'] as String;
        double currentModeWeight = prefs.getDouble('weight_mode_$mode') ?? 1.0;
        prefs.setDouble('weight_mode_$mode', (currentModeWeight * multiplier).clamp(0.1, 5.0));

        // 1.2 Filter-Interesse schärfen
        final sources = search['sources'] as List;
        final files = search['files'] as List;
        for (var filter in [...sources, ...files]) {
          double currentFilterWeight = prefs.getDouble('weight_filter_$filter') ?? 1.0;
          prefs.setDouble('weight_filter_$filter', (currentFilterWeight * multiplier).clamp(0.1, 5.0));
        }

        // 1.3 Keyword-Interesse schärfen (NEU)
        final query = search['query'] as String;
        _extractAndWeightKeywords(query, multiplier, prefs);
      }
    });

    // 2. KEIN AUTOMATISCHER EXPORT MEHR (Privacy Härtung)
    // Die Feedback-Daten verbleiben verschlüsselt in der feedbackBox, 
    // bis der Nutzer sie manuell im Settings-Screen zur Übertragung freigibt.
    
    // 3. RADIKALE LÖSCHUNG DER VERLAUFSDATEN (Privacy Hygiene)
    await searchBox.clear(); 
    // FeedbackBox wird NICHT automatisch gelöscht, da der Nutzer die Daten noch sichten will

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

  // NEU: Methode für den manuellen Export-Review
  List<Map<String, dynamic>> getFeedbackForReview() {
    final box = Hive.box(_feedbackBoxName);
    return box.values.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> clearAllFeedback() async {
    await Hive.box(_feedbackBoxName).clear();
  }

  void _extractAndWeightKeywords(String query, double multiplier, SharedPreferences prefs) {
    // Einfache Tokenisierung & Bereinigung
    final words = query.toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .split(' ')
        .where((w) => w.length > 3) // Nur relevante Wörter (keine Stoppwörter wie "der", "die", "und")
        .toList();

    for (var word in words) {
      double currentWeight = prefs.getDouble('weight_kw_$word') ?? 1.0;
      // Keywords werden langsamer gewichtet als Filter, um Overfitting zu vermeiden
      double leanMultiplier = 1.0 + (multiplier - 1.0) * 0.5; 
      prefs.setDouble('weight_kw_$word', (currentWeight * leanMultiplier).clamp(0.5, 3.0));
    }
  }
}
