import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:findux_mobile/l10n/app_localizations.dart';
import '../services/learning_service.dart';
import '../services/chrome_import_service.dart';
import '../services/haptic_helper.dart';
import '../logic/query_builder.dart';
import '../logic/state_provider.dart';
import '../logic/deep_analyzer.dart';
import '../theme.dart';
import '../utils/findux_stopwords.dart';
import '../coach/coach_models.dart';
import '../coach/precision_advisor.dart';
import '../coach/phrase_detector.dart';
import '../coach/vagueness_detector.dart';
import 'incognito_browser_screen.dart';
import 'widgets/inline_coach_section.dart';
import 'widgets/trust_debug_overlay.dart';

class HomePage extends ConsumerStatefulWidget {
  final LearningService learningService;

  const HomePage({super.key, required this.learningService});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final TextEditingController _whatController = TextEditingController();
  final TextEditingController _whyController = TextEditingController();

  bool _showFeedbackOverlay = false;
  bool _showDeepAnalysisOverlay = false;
  bool _hasSearchedOnce = false;
  bool _showAdvanced = false;
  // Stage G UX: "Warum?"-Feld ist standardmaessig versteckt — nur per Chip
  // sichtbar. Das ist der Apple-Trick fuer "ein Feld, optional mehr".
  bool _showWhyField = false;
  CoachInjection? _ambientCoachInjection;
  List<CoachChoice> _ambientCoachChoices = const [];
  List<String> _suggestedGoals = [];
  Timer? _analysisTimer;
  Timer? _intentTimer;
  String? _lastSearchId;
  String _lastIntentWord = '';

  String? _selectedRating;
  Timer? _vaguenessTimer;
  final TextEditingController _feedbackController = TextEditingController();

  // Stage 14: Pflicht-Bewertung bei NEUEN Suchrichtungen.
  // Wenn _performSearch erkennt, dass die Query Tokens enthaelt, die das
  // Lern-Modell noch nie gesehen hat, oeffnet sich nach Rueckkehr vom
  // Browser AUTOMATISCH der Bewertungs-Overlay — und ist dann nicht mehr
  // per Tap-ins-Leere oder Close-X schliessbar (mandatory mode), bis der
  // User up/down + Bewerten getippt hat. Lokaler Token-Set in
  // SharedPreferences, kein Versand, kein Cloud-State.
  bool _mandatoryRating = false;
  Set<String> _newTokensThisSearch = const <String>{};
  static const String _seenKwsKey = 'seen_query_kws';
  static const int _seenKwsCap = 5000;
  static const String _intentFreqPrefix = 'intent_freq_';

  String _viewState = 'home';
  String _previousViewState = 'home';
  PrecisionRecommendation? _advice;

  // ---------- Hardware-Trigger: Doppel-Lauter-Taste ----------
  // Wir nutzen volume_controller, weil Flutter's HardwareKeyboard die
  // Volume-Tasten auf Android nicht zuverlaessig durchreicht. Wir hoeren
  // also auf Volume-AENDERUNGEN: zwei aufeinanderfolgende Volume-up-Pulse
  // innerhalb von 600ms loesen die Suche aus. Down-Drueke werden ignoriert.

  // Quellen-Optionen (Label + interner Key)
  static const List<Map<String, String>> _sourceOptions = [
    {'v': 'alle', 'icon': '🌐', 'label': 'Alle'},
    {'v': 'foren', 'icon': '💬', 'label': 'Foren'},
    {'v': 'reddit', 'icon': '🟠', 'label': 'Reddit'},
    {'v': 'news', 'icon': '📰', 'label': 'News'},
    {'v': 'wikipedia', 'icon': '📚', 'label': 'Wikipedia'},
    {'v': 'offiziell', 'icon': '🏛️', 'label': 'Offiziell (.gov/.edu)'},
    {'v': 'academic', 'icon': '🎓', 'label': 'Akademisch'},
    {'v': 'video', 'icon': '🎥', 'label': 'Video'},
    {'v': 'blogs', 'icon': '✍️', 'label': 'Blogs'},
    {'v': 'shops', 'icon': '🛒', 'label': 'Shops'},
    {'v': 'social', 'icon': '👥', 'label': 'Sozial'},
    {'v': 'docs', 'icon': '📖', 'label': 'Docs'},
    {'v': 'code', 'icon': '💻', 'label': 'Code'},
  ];

  // Datei-Optionen
  static const List<Map<String, String>> _fileOptions = [
    {'v': 'alle', 'icon': '📄', 'label': 'Alle'},
    {'v': 'pdf', 'icon': '📕', 'label': 'PDF'},
    {'v': 'ppt', 'icon': '📊', 'label': 'PPT'},
    {'v': 'doc', 'icon': '📝', 'label': 'DOC'},
    {'v': 'xls', 'icon': '📈', 'label': 'XLS'},
    {'v': 'images', 'icon': '🖼️', 'label': 'Bilder'},
    {'v': 'audio', 'icon': '🎵', 'label': 'Audio'},
    {'v': 'video_file', 'icon': '🎬', 'label': 'Video-Datei'},
    {'v': 'archive', 'icon': '📦', 'label': 'Archiv'},
    {'v': 'ebook', 'icon': '📓', 'label': 'E-Book'},
  ];

  static const List<Map<String, String>> _modeOptions = [
    {'v': 'standard', 'icon': '⚖️', 'label': 'Standard'},
    {'v': 'precise', 'icon': '🎯', 'label': 'Praezise'},
    {'v': 'discover', 'icon': '🔍', 'label': 'Entdecken'},
    {'v': 'recent', 'icon': '🕒', 'label': 'Aktuell (12 Mon.)'},
  ];

  @override
  void initState() {
    super.initState();
    _whatController.addListener(_onWhatTextChanged);
  }

  // ---------- Intent-Popup (10s Single-Word-Trigger) ----------

  void _onWhatTextChanged() {
    final text = _whatController.text.trim();
    final words =
        text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

    if (words.length == 1 &&
        !_showWhyField &&
        _whyController.text.trim().isEmpty &&
        _viewState == 'dashboard') {
      final word = words.first;
      if (word != _lastIntentWord) {
        _lastIntentWord = word;
        _intentTimer?.cancel();
    _vaguenessTimer?.cancel();
        _intentTimer = Timer(const Duration(seconds: 10), () {
          if (mounted && _viewState == 'dashboard') {
            // ignore: discarded_futures
            _showIntentPopup(word);
          }
        });
      }
     } else {
       _intentTimer?.cancel();
       _vaguenessTimer?.cancel();
       if (text.isEmpty) _lastIntentWord = '';
     }

     // Vagueness-Check nach 15s Inaktivität
     _vaguenessTimer?.cancel();
     _vaguenessTimer = Timer(const Duration(seconds: 15), () {
       if (!mounted) return;
       if (_viewState != 'dashboard') return;
       final currentText = _whatController.text.trim();
       if (currentText.isEmpty) return;
       _checkVaguenessAndOfferSuggestions(currentText);
     });
   }

  // ---------- Intent-Lernlogik: SharedPreferences ----------

  /// Normalisiert ein Suchwort auf max. 24 Zeichen für den Prefs-Key.
  String _intentWordKey(String word) =>
      word.toLowerCase().trim().replaceAll(RegExp(r'[^\w]'), '').length > 24
          ? word.toLowerCase().trim().replaceAll(RegExp(r'[^\w]'), '').substring(0, 24)
          : word.toLowerCase().trim().replaceAll(RegExp(r'[^\w]'), '');

  /// Lädt Nutzungs-Zähler aller Intent-Keys für ein Wort.
  /// Gibt eine Map {intentKey → count} zurück.
  Future<Map<String, int>> _loadIntentFreqs(String word) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final wk = _intentWordKey(word);
      const keys = ['find', 'info', 'buy', 'guide', 'review', 'nearby'];
      final result = <String, int>{};
      for (final k in keys) {
        result[k] = prefs.getInt('$_intentFreqPrefix${wk}_$k') ?? 0;
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  /// Inkrementiert den Zähler für eine gewählte Absicht.
  Future<void> _saveIntentChoice(String word, String intentKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final wk = _intentWordKey(word);
      final prefKey = '$_intentFreqPrefix${wk}_$intentKey';
      final current = prefs.getInt(prefKey) ?? 0;
      await prefs.setInt(prefKey, current + 1);
    } catch (_) {}
  }

  Future<void> _showIntentPopup(String word) async {
    if (!mounted) return;

    // Frequenzen laden und Intents sortieren (häufigste oben).
    final freqs = await _loadIntentFreqs(word);
    if (!mounted) return;

    // Definition: key, icon, label, why
    final baseIntents = [
      {'key': 'find',   'icon': '📍', 'label': 'Wo kann ich das finden?',        'why': 'finden wo standort'},
      {'key': 'info',   'icon': 'ℹ️',  'label': 'Informationen / Was ist das?',   'why': 'informationen erklärung hintergrund'},
      {'key': 'buy',    'icon': '💰', 'label': 'Kaufen / Preise vergleichen',     'why': 'kaufen preis vergleich günstig'},
      {'key': 'guide',  'icon': '📖', 'label': 'Anleitung / Wie geht das?',      'why': 'anleitung wie tipps schritt für schritt'},
      {'key': 'review', 'icon': '⭐', 'label': 'Erfahrungen & Bewertungen',       'why': 'erfahrungen bewertungen meinungen empfehlungen'},
      {'key': 'nearby', 'icon': '🗺️', 'label': 'In meiner Nähe',                 'why': 'in meiner nähe regional lokal'},
    ];

    // Stabile Sortierung: höchster count zuerst, Gleichstand → Originalreihenfolge.
    final sorted = List<Map<String, String>>.from(baseIntents);
    sorted.sort((a, b) {
      final ca = freqs[a['key']!] ?? 0;
      final cb = freqs[b['key']!] ?? 0;
      return cb.compareTo(ca);
    });

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final topCount = freqs[sorted.first['key']!] ?? 0;
        return SafeArea(
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag-Handleconst 
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                // Titel
                Text.rich(const 
                  TextSpan(
                    children: [
                      const TextSpan(text: 'Du suchst nach '),const 
                      TextSpan(
                        text: '"$word"',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: FindUXProTheme.primaryPurple,
                        ),
                      ),
                      const TextSpan(text: '\n— was willst du damit?'),
                    ],
                  ),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                    height: 1.35,
                  ),
                ),
                // Personaliseriungs-Hinweis nur zeigen wenn mind. 1 Intent gelernt
                if (topCount >= 2) ...[
                  const SizedBox(height: 6),
                  const Text(
                    'Deine häufigste Wahl steht oben ✦',
                    style: TextStyle(
                      fontSize: 12,
                      color: FindUXProTheme.primaryPurple,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                // Intent-Optionen (sortiert)
                ...sorted.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final intent = entry.value;
                  final intentKey = intent['key']!;
                  final count = freqs[intentKey] ?? 0;
                  // Top-Intent (index 0) mit count >= 2: stärkerer Rahmen
                  final isTop = idx == 0 && count >= 2;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          Navigator.pop(ctx);
                          Haptics.tap();
                          // ignore: discarded_futures
                          _saveIntentChoice(word, intentKey);
                          setState(() {
                            _whyController.text = intent['why']!;
                            _showWhyField = true;
                          });
                        },
                        child: Ink(
                          decoration: BoxDecoration(
                            color: isTop
                                ? FindUXProTheme.primaryPurple.withValues(alpha: 0.07)
                                : const Color(0xFFF5F3FF),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isTop
                                  ? FindUXProTheme.primaryPurple.withValues(alpha: 0.55)
                                  : const Color(0xFFD4C8FF),
                              width: isTop ? 1.5 : 1.0,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 13),
                            child: Row(
                              children: [const 
                                Text(intent['icon']!,
                                    style: const TextStyle(fontSize: 22)),
                                const SizedBox(width: 14),const 
                                Expanded(
                                  child: Text(
                                    intent['label']!,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                                // Nutzungs-Badge (ab 2 Mal)
                                if (count >= 2)const 
                                  Container(
                                    margin: const EdgeInsets.only(right: 6),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: FindUXProTheme.primaryPurple
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      '${count}×',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: FindUXProTheme.primaryPurple,
                                      ),
                                    ),
                                  ),
                                const Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 14,
                                    color: Colors.black38),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                // "Selbst beschreiben" Optionconst 
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      Navigator.pop(ctx);
                      Haptics.tap();
                      setState(() => _showWhyField = true);
                    },
                    child: Ink(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        child: Row(
                          children: [const 
                            Text('✍️', style: TextStyle(fontSize: 22)),const 
                            SizedBox(width: 14),const 
                            Text(
                              'Selbst beschreiben...',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }


  @override
  void dispose() {
    _analysisTimer?.cancel();
    _intentTimer?.cancel();
    _vaguenessTimer?.cancel();
    super.dispose();
  }

  Future<void> _purgeAllSessionData() async {
    if (!mounted) return;
    setState(() {
      _suggestedGoals = const [];
      _selectedRating = null;
    _vaguenessTimer?.cancel();
      _feedbackController.clear();
      _showDeepAnalysisOverlay = false;
      _showFeedbackOverlay = false;
      // Hinweis: _mandatoryRating wird NICHT geleert — wenn der User
      // mitten in einer Pflicht-Bewertung das Results-Screen schliesst,
      // bleibt der Flag erhalten, sodass der Overlay bei der naechsten
      // Suche wieder erscheint. _purgeAllSessionData wird nur ueber den
      // X-Knopf erreicht, der ohnehin blockiert wird (siehe Results-
      // Header).
    });
  }

  // ---------- Stage 14: Pflicht-Bewertung-Helfer ----------

  /// Tokenisiert die "Was?"-Eingabe des Users analog zum Lern-Modell
  /// (selbe Stopwort-Listen, selbe Mindestlaenge, selbe Operatoren-
  /// Filterung) — wir wollen, dass "neue Tokens" hier exakt dasselbe
  /// bedeuten wie "neue Tokens" im LearningService._extractAndWeightKeywords.
  Set<String> _collectQueryTokens(String text, String language) {
    final clean = text
        .replaceAll(const 
            RegExp(
                r'\b(site|inurl|intitle|intext|filetype|ext|before|after|allintitle|allintext|allinurl):\S+'),
            ' ')
        .replaceAll(RegExp(r'-\S+'), ' ')
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .toLowerCase();
    final stopwords = stopwordsForLanguage(language);
    return clean
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 3 && !stopwords.contains(w))
        .toSet();
  }

  Future<Set<String>> _detectNewTokens(Set<String> tokens) async {
    if (tokens.isEmpty) return const <String>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen =
          (prefs.getStringList(_seenKwsKey) ?? const <String>[]).toSet();
      return tokens.difference(seen);
    } catch (e) {
      if (kDebugMode) debugPrint('detectNewTokens error: $e');
      return const <String>{};
    }
  }

  Future<void> _markTokensSeen(Set<String> tokens) async {
    if (tokens.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen =
          (prefs.getStringList(_seenKwsKey) ?? const <String>[]).toSet();
      seen.addAll(tokens);
      var list = seen.toList();
      if (list.length > _seenKwsCap) {
        list = list.sublist(list.length - _seenKwsCap);
      }
      await prefs.setStringList(_seenKwsKey, list);
    } catch (e) {
       if (kDebugMode) debugPrint('markTokensSeen error: $e');
     }
   }

  // ---------- Vagueness Detection ----------
  Future<void> _checkVaguenessAndOfferSuggestions(String text) async {
    final isVague = VaguenessDetector.isVague(what: text, why: '');
    if (!isVague) return;
    final suggestions = await _generateSuggestions(text);
    if (suggestions.isNotEmpty && mounted) {
      _showSuggestionsDialog(text, suggestions);
    }
  }

  Future<List<String>> _generateSuggestions(String text) async {
    final lower = text.toLowerCase().trim();
    final settings = ref.read(settingsProvider);
    final interests = settings.interests;

    // 1. Vorschläge aus Interessen (falls vorhanden)
    if (interests.isNotEmpty) {
      final interestSuggestions = <String>[];
      for (final interest in interests) {
        final parts = interest.split('/');
        if (parts.length >= 2) {
          final top = parts[0];
          final sub = parts[1];
          interestSuggestions.add('$sub $top');
          interestSuggestions.add('$sub $top tutorials');
          interestSuggestions.add('$top $sub');
        } else if (parts.length == 1) {
          interestSuggestions.add('$interest tutorial');
          interestSuggestions.add('$interest erklärung');
        }
      }
      final mixed = [...interestSuggestions, '${text} tutorial', '${text} beispiele']
          .take(6)
          .toList();
      return mixed;
    }

    // 2. Vorschläge aus Chrome-Chronik (häufige Suchbegriffe)
    try {
      final security = ref.read(securityServiceProvider);
      final box = await ChromeImportService.openBox(await security.getEncryptionKey());
      if (box.isOpen) {
        final all = box.values.toList();
        final queryCount = <String, int>{};
        for (final v in all) {
          if (v is Map) {
            final q = (v['q'] ?? '').toString().toLowerCase().trim();
            if (q.isNotEmpty && q != text.toLowerCase()) {
              queryCount[q] = (queryCount[q] ?? 0) + 1;
            }
          }
        }
        final sorted = queryCount.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final historyBased = <String>[];
        for (final e in sorted) {
          if (historyBased.length >= 3) break;
          if (e.key.startsWith(lower) || e.key.contains(lower)) {
            historyBased.add(e.key);
          }
        }
        if (historyBased.isNotEmpty) {
          return historyBased;
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Chronik-Vorschläge fehlgeschlagen: $e');
    }

     // 3. Fallback: Basis-Vorschläge + Intent-Erkennung
     if (lower.contains('python')) {
       return ['python listen sortieren', 'python dict auslistung', 'python tutorial'];
     }
     if (lower.contains('react')) {
       return ['react native tutorial', 'react komponenten', 'react hooks erklärung'];
     }
     if (lower.contains('javascript') || lower.contains('js')) {
       return ['javascript array methoden', 'javascript async await', 'javascript tutorial'];
     }
     if (lower.contains('finanzen') || lower.contains('geld') || lower.contains('sparen') || lower.contains('budget')) {
       return ['finanzen budget planer', 'sparen tipps', 'finanzielle beratung', 'investitionen anfangen'];
     }
     if (lower.contains('gesundheit') || lower.contains('krank') || lower.contains('symptom') || lower.contains('arzt')) {
       return ['gesundheit ratgeber', 'symptome check', 'arzt finden', 'gesunde ernährung'];
     }
     if (lower.contains('auto') || lower.contains('fahrzeug') || lower.contains('autokauf') || lower.contains('autoreparatur')) {
       return ['autokauf tipps', 'autoreparatur selbst machen', 'fahrzeug pflege'];
     }
     if (lower.contains('reisen') || lower.contains('urlaub') || lower.contains('hotel') || lower.contains('flug')) {
       return ['reisen günstig buchen', 'urlaub planen', 'reiseversicherung vergleich'];
     }
     if (lower.contains('kochen') || lower.contains('rezept') || lower.contains('backen') || lower.contains('essen')) {
       return ['rezepte einfach', 'kochen für anfänger', 'backen grundrezepte'];
     }
     if (lower.contains('sport') || lower.contains('fitness') || lower.contains('training') || lower.contains('laufen')) {
       return ['training für anfänger', 'fitness zu hause', 'sportarten vergleich'];
     }
     if (lower.contains('tech') || lower.contains('software') || lower.contains('app') || lower.contains('entwicklung')) {
       return ['software entwicklung tutorial', 'app erstellen', 'tech news'];
     }
     return ['${text} tutorial', '${text} erklärung', 'wie funktioniert ${text}', '${text} beispiele'];
   }

  void _showSuggestionsDialog(String original, List<String> suggestions) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => PopScope(
        onWillPop: () async {
          _recordVaguenessNegativeFeedback(original);
          return true;
        },
        child: AlertDialog(
          title: const Text('Möchtest du genauer suchen?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Deine Query ist etwas vage. Hier sind präzisere Vorschläge:'),
              const SizedBox(height: 12),const 
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: suggestions
                    .map((s) => ChoiceChip(
                          label: Text(s),
                          selected: false,
                          onSelected: (bool? selected) {
                            HapticFeedback.selectionClick();
                            Navigator.of(ctx).pop();
                            _replaceWhatWith(s);
                          },
                        ))
                    .toList(),
              ),
            ],
          ),
          actions: [const 
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _recordVaguenessNegativeFeedback(original);
              },
              child: const Text('Später'),
            ),const 
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                if (suggestions.isNotEmpty) {
                  _replaceWhatWith(suggestions.first);
                }
              },
              child: const Text('Ersten Vorschlag nutzen'),
            ),
          ],
        ),
      ),
    );
  }

  void _replaceWhatWith(String text) {
    setState(() {
      _whatController.text = text;
    });
    // Automatisch suchen nach Vorschlags-Auswahl
    // Kurz verzögert, damit UI-Update sichtbar ist
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted && _viewState == 'dashboard') {
        _performSearch();
      }
    });
  }

  Future<void> _recordVaguenessNegativeFeedback(String vagueTerm) async {
    final term = vagueTerm.toLowerCase().trim();
    if (term.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'weight_kw_$term';
      final cur = prefs.getDouble(key) ?? 1.0;
      final next = (cur - 0.1).clamp(0.4, 5.0);
      await prefs.setDouble(key, next);
      if (kDebugMode) {
        debugPrint('Vagueness negative feedback: $term weight set to $next');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Vagueness feedback failed: $e');
    }
  }

  Future<void> _performSearch({
    String? addedGoal,
    CoachInjection? injection,
    String? overrideQuery,
    List<Map<String, dynamic>>? coachChoices,
  }) async {
    if (_whatController.text.trim().isEmpty) return;
    _intentTimer?.cancel();
    _vaguenessTimer?.cancel();

    // A1: Bekannte Mehr-Wort-Phrasen automatisch in Anführungszeichen setzen
    // (PhraseDetector.autoQuote) — nur wenn der User noch keine Quotes gesetzt hat.
    // Controller-Text bleibt unveraendert; effectiveWhat fliesst nur in buildQuery.
    final effectiveWhat =
        PhraseDetector.autoQuote(_whatController.text.trim());

    // A2: Vagheits-Erkennung — wenn WAS + WARUM beide zu kurz/leer,
    // snackbar-Hinweis zeigen und InlineCoachSection sanft auffordern.
    final isVague = VaguenessDetector.isVague(
      what: _whatController.text.trim(),
      why: _whyController.text.trim(),
    );
    if (isVague && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Tipp: Kontext schaerft die Ergebnisse — tippe ✨ Schaerfen auf'),
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    if (_viewState != 'results') {
      _startDeepAnalysis();
    }
    HapticFeedback.lightImpact();

    final settings = ref.read(settingsProvider);
    final builder = FindUXQueryBuilder();
    final allFilters = <String>[
      ...settings.sources.where((s) => s != 'alle'),
      ...settings.files.where((s) => s != 'alle'),
    ];

    final settingsMap = <String, dynamic>{
      'plz': settings.plz,
      'beruf': settings.beruf,
      'employmentType': settings.employmentType,
      // Bug-Fix: familyStatus, jahr und interests wurden bisher nicht
      // an buildQuery/StammdatenResolver weitergegeben — alle
      // Familienstatus- und Alters-Logik sowie Interesse-Anreicherung
      // blieben dadurch wirkungslos.
      'familyStatus': settings.familyStatus,
      'jahr': settings.jahr,
      'interests': settings.interests,
      'searchengine': settings.searchEngine,
      // Stage 14: EFFECTIVE Wert verwenden — wenn das Geburtsjahr Alter
      // unter 18 ergibt, wird der Jugendschutz hart erzwungen, egal was
      // der User-Toggle sagt. So landet "&safe=active" / "&kp=1" /
      // explicit-exclusions zuverlaessig in jeder Query Minderjaehriger.
      'enableYouthProtection': settings.effectiveYouthProtection,
      'language': settings.language,
      'country': settings.country,
    };

    String contextWhy = _whyController.text;
    if (addedGoal != null) {
      contextWhy = '$contextWhy $addedGoal';
    }

    final resolvedInjection = injection ?? _ambientCoachInjection;
    final effectiveMode = resolvedInjection?.modeOverride ?? settings.mode;
    final fullQuery = overrideQuery ??
        await builder.buildQuery(
          what: effectiveWhat,
          why: contextWhy,
          filters: allFilters,
          settings: settingsMap,
          mode: effectiveMode,
          coachInjection: resolvedInjection,
        );

    final url = builder.buildSearchUrl(
        fullQuery, settings.searchEngine, settingsMap);

    // Stage 14: VOR dem Suchstart neue Tokens erkennen — danach koennten
    // sie schon als "seen" gespeichert sein.
    final tokens =
        _collectQueryTokens(_whatController.text, settings.language);
    final newTokens = await _detectNewTokens(tokens);

    if (!mounted) return;

    setState(() {
      _previousViewState = _viewState;
      _viewState = 'results';
      _showDeepAnalysisOverlay = false;
      _hasSearchedOnce = true;
    });

    // Track BEFORE Navigation/Launch — damit trackFeedback die richtige
    // search_id findet (letzter Eintrag im Hive-Box). Reihenfolge ist
    // wichtig fuer Stage 14, da der Bewertungs-Overlay direkt nach
    // Browser-Rueckkehr aufpoppt und sofort committen koennen muss.
    _lastSearchId = await widget.learningService.trackSearch(
      query: fullQuery,
      url: url,
      settings: settingsMap,
      sources: settings.sources,
      files: settings.files,
      mode: effectiveMode,
      coachChoices: coachChoices ??
          (_ambientCoachChoices.isNotEmpty
              ? _ambientCoachChoices.map((c) => c.toJson()).toList()
              : null),
    );

    final uri = Uri.tryParse(url);
    bool launched = false;
    if (uri != null) {
      try {
        if (settings.openInApp) {
          // IMMER Inkognito (eigener WebView mit incognito:true).
          // Stage 14: Navigation wird AWAITED — auf Rueckkehr aus dem
          // In-App-Browser wird unten der Pflicht-Bewertungs-Overlay
          // ausgeloest, falls neue Tokens entdeckt wurden.
          if (mounted) {
            launched = true;
            await Navigator.push<void>(
              context,const 
              MaterialPageRoute(
                builder: (_) => IncognitoBrowserScreen(url: url),
              ),
            );
          }
        } else {
          launched = await launchUrl(
              uri, mode: LaunchMode.externalApplication);
          if (!launched && mounted) _showLaunchFailedSnack();
        }
      } catch (e) {
        if (kDebugMode) debugPrint('launchUrl error: $e');
        if (mounted) _showLaunchFailedSnack();
      }
    }

    // Stage 14: Pflicht-Bewertung. Wir markieren die Tokens als "seen"
    // BEVOR der Overlay erscheint — selbst wenn der User bewusst die App
    // killt, wird die gleiche Suche beim naechsten Mal nicht mehr als
    // "neu" erkannt (wir tracken nur "schonmal probiert", nicht "schon
    // bewertet"). Das ist die Apple-konforme Variante: kein endloser
    // Loop, aber ein einmaliger Pflicht-Touchpoint pro Suchrichtung.
    if (mounted && launched && newTokens.isNotEmpty) {
      if (mounted) {
        setState(() {
          _newTokensThisSearch = newTokens;
          _mandatoryRating = true;
          _showFeedbackOverlay = true;
        });
      }
    }

    // Stil-Analyzer nach jeder Suche neu laden (asynchron, blockiert nichts)
    // ignore: discarded_futures
    PrecisionAdvisor.analyze().then((rec) {
      if (mounted) setState(() => _advice = rec);
    });

  }

  


  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: Stack(
        children: [const 
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final forward =
                  _viewRank(_viewState) >= _viewRank(_previousViewState);
              final slide = Tween<Offset>(
                begin: Offset(forward ? 0.06 : -0.06, 0),
                end: Offset.zero,
              ).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: slide, child: child),
              );
            },
            child: _getViewForState(),
          ),
          // Debug-Overlay: nur in Debug-Builds sichtbar.
          // Im Release-Build wird dieser Block vom Compiler
          // vollstaendig eliminiert (kDebugMode = const false).
          if (kDebugMode)
            ValueListenableBuilder<QueryDebugInfo?>(
              valueListenable: QueryDebugInfo.notifier,
              builder: (_, info, __) => info == null
                  ? const SizedBox.shrink()
                  : TrustDebugOverlay(info: info),
            ),
        ],
      ),
    );
  }

  int _viewRank(String state) {
    const order = {'home': 0, 'dashboard': 1, 'results': 2};
    return order[state] ?? 0;
  }

  Widget _getViewForState() {
    switch (_viewState) {
      case 'home':
        return _buildHomeScreen(key: const ValueKey('home'));
      case 'dashboard':
        return _buildSearchDashboard(key: const ValueKey('dashboard'));
      case 'results':
        return _buildResultsScreen(key: const ValueKey('results'));
      default:
        return _buildHomeScreen(key: const ValueKey('home'));
    }
  }

  void _startDeepAnalysis() {
    _analysisTimer?.cancel();
    _analysisTimer = Timer(const Duration(seconds: 30), () async {
      if (_viewState == 'results' && mounted) {
        final results =
            await DeepAnalyzer.analyzeResults(_whatController.text, {});
        if (mounted) {
          setState(() {
            _suggestedGoals = results;
            _showDeepAnalysisOverlay = true;
          });
          HapticFeedback.heavyImpact();
        }
      }
    });
  }

  void _showLaunchFailedSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Suchergebnis konnte nicht geoeffnet werden.'),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  Future<void> _submitFeedback() async {
    if (_selectedRating == null) return;
    HapticFeedback.mediumImpact();
    await widget.learningService.trackFeedback(
      _selectedRating!,
      comment: _feedbackController.text.trim(),
      searchId: _lastSearchId,
    );
    // Tokens erst nach Bewertung als gesehen markieren
    if (_newTokensThisSearch.isNotEmpty) {
      await _markTokensSeen(_newTokensThisSearch);
    }
    setState(() {
      _showFeedbackOverlay = false;
      _selectedRating = null;
      _feedbackController.clear();
      _mandatoryRating = false;
      _newTokensThisSearch = const <String>{};
      _lastSearchId = null;
    });
  }

  // ---------- Home (Premium-Look) ----------

  Widget _buildHomeScreen({Key? key}) {
    final l10n = AppLocalizations.of(context)!;
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        physics: const BouncingScrollPhysics(),
      ),
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height -
                MediaQuery.of(context).padding.vertical,
          ),
          child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(gradient: FindUXProTheme.primaryGradient),
            child: SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  const SizedBox(height: 40),
                  Image.asset(
                    'assets/logo.png',
                    width: 220,
                    height: 220,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.search,
                      size: 160,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 10),const 
                  Text(
                    'FindYouX',
                    style: FindUXProTheme.headlineStyle.copyWith(
                      fontSize: 42,
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                    ),
                  ),const 
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Column(
                      children: [
                        _buildMenuButton(
                          title: l10n.startSearch,
                          icon: Icons.search_rounded,
                          onTap: () => setState(() {
                            _previousViewState = _viewState;
                            _viewState = 'dashboard';
                          }),
                        ),
                        const SizedBox(height: 16),
                        _buildMenuButton(
                          title: l10n.settingsTitle,
                          icon: Icons.settings_rounded,
                          onTap: () => Navigator.pushNamed(context, '/settings'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 60),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildMenuButton(
      {required String title,
      required IconData icon,
      required VoidCallback onTap}) {
    return _AnimatedScaleButton(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          borderRadius: FindUXProTheme.largeSquircleRadius,
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [const 
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 12),const 
            Icon(icon, color: Colors.white, size: 22),
          ],
        ),
      ),
    );
  }
  // ---------- Search Dashboard (Stage G — Apple-UX) ----------
  // Frueher: 2 gleichberechtigte TextFields, Mid-Card-Button.
  // Jetzt: EIN grosses Hero-Feld mit Auto-Fokus, optionaler "Kontext"-
  // Chip blendet das Why-Feld sanft ein. Such-CTA klebt unten in
  // Daumen-Reichweite — wie Apple Maps/Mail/Messages.
  Widget _buildSearchDashboard({Key? key}) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(settingsProvider);
    return Container(
      key: key,
      color: const Color(0xFFF5F5F7),
      child: SafeArea(
        child: Column(
          children: [
            // Header — bewusst leise, kein Titel-Wettbewerb mit Hero-Feldconst 
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
              child: Row(
                children: [const 
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.black87, size: 20),
                    onPressed: () {
                      Haptics.tap();
                      setState(() { _previousViewState = _viewState; _viewState = 'home'; });
                    },
                  ),
                  const Spacer(),const 
                  IconButton(
                    icon: const Icon(Icons.settings_outlined,
                        color: Colors.black54),
                    onPressed: () {
                      Haptics.tap();
                      Navigator.pushNamed(context, '/settings');
                    },
                  ),
                ],
              ),
            ),const 
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Hero-Frage
                    const Text(
                      'Was suchst du?',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                        letterSpacing: -1.0,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildStammdatenPill(),
                    _buildAdvicePill(),
                    // EIN grosses, fokussiertes Eingabefeld
                    _buildHeroSearchField(
                      controller: _whatController,
                      hint: l10n.topicHint,
                    ),
                    const SizedBox(height: 12),
                    // Optionaler Kontext-Chip (Apple-Pattern: "+ Hinzufuegen")
                    if (!_showWhyField)
                      _buildContextChip(
                        onTap: () {
                          Haptics.tap();
                          _intentTimer?.cancel();
    _vaguenessTimer?.cancel();
                          setState(() => _showWhyField = true);
                        },
                      ),
                    if (_showWhyField) ...[
                      _buildSecondaryInput(
                        controller: _whyController,
                        hint: l10n.reasonHint,
                        icon: Icons.psychology_outlined,
                        onClear: () {
                          Haptics.tap();
                          _whyController.clear();
                          setState(() => _showWhyField = false);
                        },
                      ),
                    ],
                    const SizedBox(height: 12),
                    // Stage 18: Ambient Coach (immer sichtbar, nie aufdringlich)const 
                    InlineCoachSection(
                      what: _whatController.text,
                      why: _whyController.text,
                      onChanged: (inj, choices) => setState(() {
                        _ambientCoachInjection = inj.isEmpty ? null : inj;
                        _ambientCoachChoices = inj.isEmpty
                            ? const []
                            : List.unmodifiable(choices);
                      }),
                    ),
                    const SizedBox(height: 20),
                    // Erweiterte Suche -> nur sichtbar nach erster Suche
                    if (_hasSearchedOnce) _buildAdvancedExpander(settings),
                    if (_hasSearchedOnce) const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            // Sticky Search-CTA — unten, Daumen-Reichweiteconst 
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F7),
                border: Border(
                  top: BorderSide(
                    color: Colors.black.withValues(alpha: 0.05),
                    width: 0.5,
                  ),
                ),
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: FindUXProTheme.primaryPurple,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [const 
                    BoxShadow(
                      color: FindUXProTheme.primaryPurple
                          .withValues(alpha: 0.30),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      Haptics.done();
                      _performSearch();
                    },
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 60),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.bolt_rounded,
                              color: Colors.white, size: 22),
                          const SizedBox(width: 10),const 
                          Text(
                            l10n.startAnalysis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStammdatenPill() {
    final settings = ref.watch(settingsProvider);
    final plz = settings.plz.trim();
    final beruf = settings.beruf.trim();
    final familyStatus = settings.familyStatus;
    const familyLabels = <String, String>{
      'familie': 'Familie',
      'alleinerziehend': 'Alleinerz.',
    };
    final familyLabel = familyLabels[familyStatus];
    if (plz.isEmpty && beruf.isEmpty && familyLabel == null) {
      return GestureDetector(
        onTap: () => Navigator.pushNamed(context, '/settings'),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
          ),
          child: Row(children: const [const 
            Icon(Icons.info_outline, size: 18, color: Colors.amber),const 
            SizedBox(width: 8),const 
            Expanded(
              child: Text(
                'Stammdaten ergaenzen: PLZ, Beruf oder Familienstatus',
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ),const 
            Icon(Icons.arrow_forward_ios, size: 12, color: Colors.black54),
          ]),
        ),
      );
    }
    final parts = <String>[];
    if (plz.isNotEmpty) parts.add('PLZ $plz');
    if (beruf.isNotEmpty) parts.add(beruf);
    if (familyLabel != null) parts.add(familyLabel);
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/settings'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: FindUXProTheme.primaryPurple.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: FindUXProTheme.primaryPurple.withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          const Icon(Icons.verified_user_outlined,
              size: 16, color: FindUXProTheme.primaryPurple),
          const SizedBox(width: 8),const 
          Expanded(
            child: Text(
              parts.join('  ·  '),
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87),
            ),
          ),
          const Icon(Icons.edit_outlined, size: 14, color: Colors.black54),
        ]),
      ),
    );
  }

  Widget _buildAdvicePill() {
    final adv = _advice;
    if (adv == null || !adv.hasData) return const SizedBox.shrink();

    final hasFilter = adv.filterHint.isNotEmpty;
    final hasTheme  = adv.topThemeLabel != null;
    // Padding leicht erhoehen wenn mehrere Zeilen sichtbar werden.
    final vertPad   = (hasFilter || hasTheme) ? 10.0 : 8.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: vertPad),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.green.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Zeile 1: Modus · Woerter · Zufriedenheit (immer sichtbar)const 
          Row(children: [
            const Icon(Icons.psychology_alt_outlined,
                size: 16, color: Colors.green),
            const SizedBox(width: 8),const 
            Expanded(
              child: Text(
                adv.summary,
                style: const TextStyle(fontSize: 11, color: Colors.black87),
              ),
            ),
          ]),
          // Zeile 2: Top-Quellen (nur wenn weight_filter_* > 1.1 vorhanden)
          if (hasFilter) ...[
            const SizedBox(height: 5),const 
            Row(children: [
              const Icon(Icons.library_books_outlined,
                  size: 14, color: Colors.green),
              const SizedBox(width: 8),const 
              Expanded(
                child: Text(
                  'Top-Quellen: ${adv.filterHint}',
                  style: const TextStyle(
                      fontSize: 11, color: Colors.black54),
                ),
              ),
            ]),
          ],
          // Zeile 3: Bevorzugtes Coach-Theme (nur wenn Theme-Feedback vorliegt)
          if (hasTheme) ...[
            const SizedBox(height: 5),const 
            Row(children: [
              const Icon(Icons.lightbulb_outline,
                  size: 14, color: Colors.green),
              const SizedBox(width: 8),const 
              Expanded(
                child: Text(
                  'Haeufiges Thema: ${adv.topThemeLabel}',
                  style: const TextStyle(
                      fontSize: 11, color: Colors.black54),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  // Hero-Suchfeld — gross, prominent, autofokus, runde Pill.
  Widget _buildHeroSearchField({
    required TextEditingController controller,
    required String hint,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [const 
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, 4)),
        ],
      ),
      padding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.search_rounded,
              color: FindUXProTheme.primaryPurple, size: 24),
          const SizedBox(width: 14),const 
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              // Stage F Haertung: keine IME-Lerndaten / Auto-Korrektur.
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              smartDashesType: SmartDashesType.disabled,
              smartQuotesType: SmartQuotesType.disabled,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) {
                Haptics.done();
                _performSearch();
              },
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                  color: Colors.black.withValues(alpha: 0.30),
                  fontWeight: FontWeight.w500,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 18),
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, v, __) => v.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.cancel_rounded,
                        size: 20, color: Colors.black26),
                    onPressed: () {
                      Haptics.tap();
                      controller.clear();
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // "+ Kontext hinzufuegen"-Chip (Apple-Pattern)
  Widget _buildContextChip({required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: FindUXProTheme.primaryPurple.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                FindUXProTheme.primaryPurple.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [const 
            Icon(Icons.add_rounded,
                size: 16, color: FindUXProTheme.primaryPurple),const 
            SizedBox(width: 6),const 
            Text(
              'Kontext hinzufuegen',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: FindUXProTheme.primaryPurple,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Sekundaeres Input-Feld fuer den optionalen "Warum?"-Kontext.
  Widget _buildSecondaryInput({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required VoidCallback onClear,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [const 
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [const 
          Icon(icon,
              color: FindUXProTheme.primaryPurple, size: 20),
          const SizedBox(width: 10),const 
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              smartDashesType: SmartDashesType.disabled,
              smartQuotesType: SmartQuotesType.disabled,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: Colors.black26),
                border: InputBorder.none,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),const 
          IconButton(
            icon: const Icon(Icons.close_rounded,
                size: 18, color: Colors.black38),
            onPressed: onClear,
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedExpander(SettingsState settings) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [const 
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _showAdvanced,
          onExpansionChanged: (v) => setState(() => _showAdvanced = v),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding:
              const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: const Icon(Icons.tune,
              color: FindUXProTheme.primaryPurple),
          title: const Text('Erweiterte Suche',
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 15)),
          subtitle: Text(
            _advancedSummary(settings),
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          iconColor: FindUXProTheme.primaryPurple,
          collapsedIconColor: Colors.black45,
          children: [
            _filterGroup(
              title: 'Such-Modus',
              items: _modeOptions,
              selected: [settings.mode],
              singleSelect: true,
              onTap: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateField(mode: v),
            ),
            const SizedBox(height: 12),
            _filterGroup(
              title: 'Quellen',
              items: _sourceOptions,
              selected: settings.sources,
              singleSelect: false,
              onTap: (v) => _toggleMulti('sources', v, settings.sources),
            ),
            const SizedBox(height: 12),
            _filterGroup(
              title: 'Dateitypen',
              items: _fileOptions,
              selected: settings.files,
              singleSelect: false,
              onTap: (v) => _toggleMulti('files', v, settings.files),
            ),
          ],
        ),
      ),
    );
  }

  String _advancedSummary(SettingsState s) {
    final modeLabel = _modeOptions
        .firstWhere((m) => m['v'] == s.mode,
            orElse: () => {'label': s.mode})['label'];
    final src = s.sources.contains('alle')
        ? 'alle Quellen'
        : '${s.sources.length} Quellen';
    final fil = s.files.contains('alle')
        ? 'alle Dateitypen'
        : '${s.files.length} Dateitypen';
    return '$modeLabel · $src · $fil';
  }

  void _toggleMulti(String which, String tapped, List<String> current) {
    final notifier = ref.read(settingsProvider.notifier);
    List<String> next = List.from(current);
    if (tapped == 'alle') {
      next = ['alle'];
    } else {
      if (next.contains(tapped)) {
        next.remove(tapped);
        if (next.isEmpty || next.every((e) => e == 'alle')) {
          next = ['alle'];
        }
      } else {
        next.add(tapped);
        next.remove('alle');
      }
    }
    if (which == 'sources') {
      notifier.updateField(sources: next);
    } else {
      notifier.updateField(files: next);
    }
  }

  Widget _filterGroup({
    required String title,
    required List<Map<String, String>> items,
    required List<String> selected,
    required bool singleSelect,
    required void Function(String) onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [const 
        Text(title,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Colors.black54)),
        const SizedBox(height: 8),const 
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items.map((item) {
            final v = item['v']!;
            final isSel = selected.contains(v);
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onTap(v);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isSel
                      ? FindUXProTheme.primaryPurple
                      : const Color(0xFFF0F0F5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${item['icon']} ${item['label']}',
                  style: TextStyle(
                    color: isSel ? Colors.white : Colors.black87,
                    fontSize: 13,
                    fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ---------- Results-Screen ----------

  Widget _buildResultsScreen({Key? key}) {
    return Container(
      key: key,
      color: const Color(0xFFF5F5F7),
      child: Column(
        children: [const 
          Container(
            padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top, bottom: 8),
            decoration:
                const BoxDecoration(color: FindUXProTheme.primaryPurple),
            child: Row(
              children: [const 
                IconButton(
                  icon: Icon(Icons.close,
                      color: _mandatoryRating
                          ? Colors.white38
                          : Colors.white,
                      size: 22),
                  // Stage 14: Wenn eine Pflicht-Bewertung offen ist, wird
                  // der Schliessen-X-Knopf deaktiviert. So kommt der User
                  // nicht aus dem Results-Screen heraus, ohne die neue
                  // Suchrichtung bewertet zu haben.
                  onPressed: _mandatoryRating
                      ? null
                      : () async {
                          _analysisTimer?.cancel();
                          await _purgeAllSessionData();
                          if (!mounted) return;
                          setState(() { _previousViewState = _viewState; _viewState = 'dashboard'; });
                        },
                ),const 
                Expanded(
                  child: Text(
                    'Suche: ${_whatController.text}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),const 
                IconButton(
                  icon: const Icon(Icons.refresh,
                      color: Colors.white, size: 22),
                  onPressed: () => _performSearch(),
                  tooltip: 'Im Browser erneut oeffnen',
                ),
              ],
            ),
          ),const 
          Expanded(
            child: Stack(
              children: [const 
                Container(
                  color: Colors.white,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.open_in_browser,
                              size: 64,
                              color: FindUXProTheme.primaryPurple),
                          const SizedBox(height: 16),
                          const Text('Im Browser geoeffnet',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center),
                          const SizedBox(height: 8),
                          const Text(
                            'Deine optimierte Suchanfrage laeuft jetzt im Browser.\nKomme zurueck und gib Feedback.',
                            style: TextStyle(
                                color: Colors.grey, fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),const 
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: FindUXProTheme.primaryPurple
                                  .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                const Text('Deine Suchanfrage:',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),const 
                                Text('"${_whatController.text}"',
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontStyle: FontStyle.italic),
                                    textAlign: TextAlign.center),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor:
                                  FindUXProTheme.primaryPurple,
                              side: const BorderSide(
                                  color: FindUXProTheme.primaryPurple),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () =>
                                setState(() { _previousViewState = _viewState; _viewState = 'dashboard'; }),
                            icon: const Icon(Icons.tune),
                            label: const Text('Erweiterte Suche'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),const 
                Positioned(
                  bottom: 30,
                  left: 20,
                  right: 20,
                  child: SafeArea(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [const 
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: FindUXProTheme.primaryPurple
                                .withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.arrow_back_ios_new,
                                color: Colors.white, size: 20),
                            onPressed: () => setState(
                                () { setState(() { _previousViewState = _viewState; _viewState = 'dashboard'; }); }),
                          ),
                        ),const 
                        GestureDetector(
                          onTap: () => setState(() =>
                              _showFeedbackOverlay = !_showFeedbackOverlay),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            decoration: BoxDecoration(
                              color: FindUXProTheme.primaryPurple,
                              borderRadius: BorderRadius.circular(30),
                              boxShadow: [const 
                                BoxShadow(
                                    color: Colors.black
                                        .withValues(alpha: 0.3),
                                    blurRadius: 10,
                                    offset: const Offset(0, 5))
                              ],
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.psychology,
                                    color: Colors.white, size: 20),
                                const SizedBox(width: 8),const 
                                Text(
                                    AppLocalizations.of(context)!
                                        .learningMode,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showDeepAnalysisOverlay) _buildDeepAnalysisOverlay(),
                if (_showFeedbackOverlay) _buildEnhancedFeedbackOverlay(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Overlays ----------

  Widget _buildDeepAnalysisOverlay() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => _showDeepAnalysisOverlay = false),
        child: Container(
          color: Colors.black45,
          child: Center(
            child: Container(
              margin: const EdgeInsets.all(32),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_awesome,
                      color: FindUXProTheme.primaryPurple, size: 40),
                  const SizedBox(height: 16),
                  const Text('Praezisierung noetig',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 22)),
                  const SizedBox(height: 8),
                  const Text(
                    'Welches Ziel verfolgst du genau?',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54, fontSize: 14),
                  ),
                  const SizedBox(height: 24),const 
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _suggestedGoals
                        .map((goal) => GestureDetector(
                              onTap: () {
                                HapticFeedback.mediumImpact();
                                _performSearch(addedGoal: goal);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: FindUXProTheme.primaryPurple
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(goal,
                                    style: const TextStyle(
                                        color: FindUXProTheme.primaryPurple,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 24),const 
                  TextButton(
                    onPressed: () => setState(
                        () => _showDeepAnalysisOverlay = false),
                    child: const Text('Aktuelle Ansicht beibehalten',
                        style: TextStyle(color: Colors.grey)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEnhancedFeedbackOverlay() {
    // Stage 14: Pflicht-Modus erkennt mandatoryRating und sperrt das
    // Backdrop-Tap, zeigt einen roten "Pflicht"-Header und listet die
    // neu gelernten Tokens als Chips auf — damit der User versteht,
    // WARUM diese Bewertung gerade noetig ist.
    final mandatory = _mandatoryRating;
    final newTokens = _newTokensThisSearch;
    final tokenPreview = newTokens.take(6).toList();
    final extraCount = newTokens.length - tokenPreview.length;

    return Positioned.fill(
      child: GestureDetector(
        // Backdrop-Tap schliesst nur, wenn NICHT pflicht.
        onTap: () {
          if (mandatory) return;
          FocusScope.of(context).unfocus();
          setState(() => _showFeedbackOverlay = false);
        },
        child: Container(
          color: mandatory ? Colors.black87 : Colors.black45,
          child: Center(
            child: SingleChildScrollView(
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: mandatory
                      ? Border.all(
                          color: const Color(0xFFE53935), width: 2)
                      : null,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (mandatory) ...[const 
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE53935)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [const 
                            Icon(Icons.priority_high_rounded,
                                color: Color(0xFFE53935), size: 16),const 
                            SizedBox(width: 4),const 
                            Text('Bewertung erforderlich',
                                style: TextStyle(
                                    color: Color(0xFFE53935),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text('Neue Suchrichtung',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 20)),
                      const SizedBox(height: 8),
                      const Text(
                        'Dein Lern-Modell hat zu diesen Begriffen noch keine '
                        'Gewichtung. Eine kurze Bewertung hilft, kuenftig '
                        'praezisere Treffer fuer dich zu finden.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.black54, fontSize: 13, height: 1.4),
                      ),
                      if (tokenPreview.isNotEmpty) ...[
                        const SizedBox(height: 14),const 
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          alignment: WrapAlignment.center,
                          children: [
                            for (final t in tokenPreview)const 
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: FindUXProTheme.primaryPurple
                                      .withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(t,
                                    style: const TextStyle(
                                        color: FindUXProTheme.primaryPurple,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                              ),
                            if (extraCount > 0)const 
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black12,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text('+$extraCount',
                                    style: const TextStyle(
                                        color: Colors.black54,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700)),
                              ),
                          ],
                        ),
                      ],
                    ] else ...[
                      const Text('Spezifizierung praezise?',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 20)),
                      const SizedBox(height: 12),
                      const Text(
                          'Dieses Feedback verfeinert die Gewichtung '
                          'deiner persoenlichen Daten.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.black54, fontSize: 14)),
                    ],
                    const SizedBox(height: 24),const 
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildFeedbackIcon(
                            Icons.thumb_down_alt_outlined, 'down', Colors.red),
                        _buildFeedbackIcon(
                            Icons.thumb_up_alt_outlined, 'up', Colors.green),
                      ],
                    ),
                    const SizedBox(height: 24),const 
                    CupertinoTextField(
                      controller: _feedbackController,
                      placeholder: 'Details zur Sitzung (optional)...',
                      maxLines: 3,
                      padding: const EdgeInsets.all(12),
                      // Stage F Haertung: Feedback-Text bleibt strikt
                      // lokal — IME-Personalisierung deaktiviert.
                      autocorrect: false,
                      enableSuggestions: false,
                      enableIMEPersonalizedLearning: false,
                      smartDashesType: SmartDashesType.disabled,
                      smartQuotesType: SmartQuotesType.disabled,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F0F5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    const SizedBox(height: 24),const 
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _selectedRating != null
                              ? FindUXProTheme.primaryPurple
                              : Colors.grey,
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed:
                            _selectedRating != null ? _submitFeedback : null,
                        child: Text(mandatory
                            ? 'Bewertung speichern'
                            : 'Sitzung bewerten'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeedbackIcon(IconData icon, String rating, Color color) {
    final isSelected = _selectedRating == rating;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedRating = rating);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.2)
              : color.withValues(alpha: 0.05),
          shape: BoxShape.circle,
          border: Border.all(
              color: isSelected ? color : Colors.transparent, width: 2),
        ),
        child: Icon(icon, color: color, size: 36),
      ),
    );
  }
}

class _AnimatedScaleButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _AnimatedScaleButton({required this.child, required this.onTap});

  @override
  State<_AnimatedScaleButton> createState() => _AnimatedScaleButtonState();
}

class _AnimatedScaleButtonState extends State<_AnimatedScaleButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        HapticFeedback.lightImpact();
        _controller.forward();
      },
      onTapUp: (_) => _controller.reverse(),
      onTapCancel: () => _controller.reverse(),
      onTap: widget.onTap,
      child: ScaleTransition(scale: _scaleAnimation, child: widget.child),
    );
  }
}
