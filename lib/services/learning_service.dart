import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LearningService {
  static const String _boxName = 'learning_data';
  static const String _logBoxName = 'learning_log';
  static const String _feedbackBoxName = 'learning_feedback';

  bool _initialized = false;

  /// Oeffnet alle Lern-Boxen verschluesselt mit dem uebergebenen Cipher-Key.
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
  }) async {
    if (!Hive.isBoxOpen(_boxName)) return;
    final box = Hive.box<dynamic>(_boxName);
    final key = DateTime.now().millisecondsSinceEpoch.toString();
    await box.put(key, <String, dynamic>{
      'query': query,
      'url': url,
      'timestamp': DateTime.now().toIso8601String(),
      'sources': sources,
      'files': files,
      'mode': mode,
    });
  }

  Future<void> trackFeedback(String rating, {String? comment}) async {
    if (!Hive.isBoxOpen(_feedbackBoxName) || !Hive.isBoxOpen(_boxName)) return;
    final box = Hive.box<dynamic>(_feedbackBoxName);
    final searchBox = Hive.box<dynamic>(_boxName);

    String? lastSearchId;
    if (searchBox.isNotEmpty) {
      lastSearchId = searchBox.keys.last.toString();
    }

    final key = DateTime.now().millisecondsSinceEpoch.toString();
    await box.put(key, <String, dynamic>{
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
    if (!Hive.isBoxOpen(_boxName) || !Hive.isBoxOpen(_feedbackBoxName)) return;
    final searchBox = Hive.box<dynamic>(_boxName);
    final feedbackBox = Hive.box<dynamic>(_feedbackBoxName);

    final searchData = Map<dynamic, dynamic>.from(searchBox.toMap());
    final feedbackData = Map<dynamic, dynamic>.from(feedbackBox.toMap());
    final prefs = await SharedPreferences.getInstance();

    for (final entry in feedbackData.entries) {
      final fValue = Map<String, dynamic>.from(entry.value as Map);
      final searchId = fValue['search_id'];
      final rating = fValue['rating'];
      final multiplier = (rating == 'up') ? 1.1 : 0.85;

      if (searchId == null || !searchData.containsKey(searchId)) continue;
      final search = Map<String, dynamic>.from(searchData[searchId] as Map);

      final mode = (search['mode'] as String?) ?? 'standard';
      final currentModeWeight = prefs.getDouble('weight_mode_$mode') ?? 1.0;
      await prefs.setDouble(
        'weight_mode_$mode',
        (currentModeWeight * multiplier).clamp(0.1, 5.0),
      );

      final sources = (search['sources'] as List<dynamic>?) ?? const <dynamic>[];
      final files = (search['files'] as List<dynamic>?) ?? const <dynamic>[];
      for (final filter in [...sources, ...files]) {
        final currentFilterWeight =
            prefs.getDouble('weight_filter_$filter') ?? 1.0;
        await prefs.setDouble(
          'weight_filter_$filter',
          (currentFilterWeight * multiplier).clamp(0.1, 5.0),
        );
      }

      final query = (search['query'] as String?) ?? '';
      await _extractAndWeightKeywords(query, multiplier, prefs);
    }

    await searchBox.clear();
    await _logPrivacyAction(
        'Interessen-Modell verfeinert. Verlaufs-Hygiene durchgefuehrt.');
  }

  Future<void> _logPrivacyAction(String message) async {
    if (!Hive.isBoxOpen(_logBoxName)) return;
    final logBox = Hive.box<dynamic>(_logBoxName);
    await logBox.add(<String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'action': 'interest_model_refinement',
      'message': message,
    });
  }

  List<Map<String, dynamic>> getFeedbackForReview() {
    if (!Hive.isBoxOpen(_feedbackBoxName)) return const <Map<String, dynamic>>[];
    final box = Hive.box<dynamic>(_feedbackBoxName);
    return box.values
        .map((dynamic e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> clearAllFeedback() async {
    if (!Hive.isBoxOpen(_feedbackBoxName)) return;
    await Hive.box<dynamic>(_feedbackBoxName).clear();
  }

  Future<void> _extractAndWeightKeywords(
      String query, double multiplier, SharedPreferences prefs) async {
    final words = query
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .split(' ')
        .where((w) => w.length > 3)
        .toList();

    for (final word in words) {
      final currentWeight = prefs.getDouble('weight_kw_$word') ?? 1.0;
      final leanMultiplier = 1.0 + (multiplier - 1.0) * 0.5;
      await prefs.setDouble(
        'weight_kw_$word',
        (currentWeight * leanMultiplier).clamp(0.5, 3.0),
      );
    }
    if (kDebugMode) {
      debugPrint('Updated keyword weights: ${words.length} terms');
    }
  }
}
