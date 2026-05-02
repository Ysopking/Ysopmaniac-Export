import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:volume_controller/volume_controller.dart';

import 'package:findux_mobile/l10n/app_localizations.dart';
import '../services/learning_service.dart';
import '../services/haptic_helper.dart';
import '../logic/query_builder.dart';
import '../logic/state_provider.dart';
import '../logic/deep_analyzer.dart';
import '../theme.dart';
import '../utils/findux_stopwords.dart';
import '../coach/coach_models.dart';
import '../coach/coach_screen.dart';
import '../coach/theme_detector.dart';
import '../coach/precision_advisor.dart';
import 'incognito_browser_screen.dart';
import 'widgets/inline_coach_section.dart';

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
  List<String> _suggestedGoals = [];
  Timer? _analysisTimer;

  String? _selectedRating;
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

  String _viewState = 'home';
  PrecisionRecommendation? _advice;

  // ---------- Hardware-Trigger: Doppel-Lauter-Taste ----------
  // Wir nutzen volume_controller, weil Flutter's HardwareKeyboard die
  // Volume-Tasten auf Android nicht zuverlaessig durchreicht. Wir hoeren
  // also auf Volume-AENDERUNGEN: zwei aufeinanderfolgende Volume-up-Pulse
  // innerhalb von 600ms loesen die Suche aus. Down-Drueke werden ignoriert.
  double? _lastVolume;
  DateTime? _lastUpAt;
  bool _volumeListenerActive = false;

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
    _loadAdvice();
    _maybeStartVolumeListener();
  }

  Future<void> _maybeStartVolumeListener() async {
    if (kIsWeb) return;
    try {
      // Aktuelle Lautstaerke einmal lesen, damit unser "rising"-Vergleich
      // nicht beim ersten Event faelschlich auslost.
      final v = await VolumeController().getVolume();
      _lastVolume = v;
    } catch (_) {}
    if (!mounted) return;
    VolumeController().listener((volume) {
      // Setting darf live umgeschaltet werden
      final enabled =
          ref.read(settingsProvider).enableVolumeShortcut;
      if (!enabled) {
        _lastVolume = volume;
        return;
      }
      // Nur reagieren wenn wir auf der Home-/Dashboard-Ansicht sind,
      // NICHT in einem In-App-Browser oder modal Dialog.
      if (_viewState == 'results') {
        _lastVolume = volume;
        return;
      }
      if (_lastVolume != null && volume > _lastVolume! + 0.001) {
        final now = DateTime.now();
        if (_lastUpAt != null &&
            now.difference(_lastUpAt!).inMilliseconds < 600) {
          _lastUpAt = null;
          if (_whatController.text.trim().isNotEmpty) {
            HapticFeedback.mediumImpact();
            // ignore: discarded_futures
            _performSearch();
          }
        } else {
          _lastUpAt = now;
        }
      }
      _lastVolume = volume;
    });
    _volumeListenerActive = true;
  }

  Future<void> _loadAdvice() async {
    final r = await PrecisionAdvisor.analyze();
    if (mounted) setState(() => _advice = r);
  }

  @override
  void dispose() {
    _analysisTimer?.cancel();
    if (_volumeListenerActive) {
      try {
        VolumeController().removeListener();
      } catch (_) {}
    }
    _whatController.dispose();
    _whyController.dispose();
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _purgeAllSessionData() async {
    if (!mounted) return;
    setState(() {
      _suggestedGoals = const [];
      _selectedRating = null;
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
        .replaceAll(
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
      debugPrint('detectNewTokens error: $e');
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
      debugPrint('markTokensSeen error: $e');
    }
  }

  Future<void> _performSearch({
    String? addedGoal,
    CoachInjection? injection,
    String? overrideQuery,
    List<Map<String, dynamic>>? coachChoices,
  }) async {
    if (_whatController.text.trim().isEmpty) return;

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
          what: _whatController.text,
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
      _viewState = 'results';
      _showDeepAnalysisOverlay = false;
      _hasSearchedOnce = true;
    });

    // Track BEFORE Navigation/Launch — damit trackFeedback die richtige
    // search_id findet (letzter Eintrag im Hive-Box). Reihenfolge ist
    // wichtig fuer Stage 14, da der Bewertungs-Overlay direkt nach
    // Browser-Rueckkehr aufpoppt und sofort committen koennen muss.
    await widget.learningService.trackSearch(
      query: fullQuery,
      url: url,
      settings: settingsMap,
      sources: settings.sources,
      files: settings.files,
      mode: effectiveMode,
      coachChoices: coachChoices,
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
              context,
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
        debugPrint('launchUrl error: $e');
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
      await _markTokensSeen(newTokens);
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

  

  // ---------- Home (Premium-Look) ----------

  Widget _buildHomeScreen({Key? key}) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      key: key,
      width: double.infinity,
      decoration: const BoxDecoration(gradient: FindUXProTheme.primaryGradient),
      child: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.vertical,
            ),
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
                const SizedBox(height: 10),
                Text(
                  'FindYouX',
                  style: FindUXProTheme.headlineStyle.copyWith(
                    fontSize: 42,
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Column(
                    children: [
                      _buildMenuButton(
                        title: l10n.startSearch,
                        icon: Icons.search_rounded,
                        onTap: () =>
                            setState(() => _viewState = 'dashboard'),
                      ),
                      const SizedBox(height: 16),
                      _buildMenuButton(
                        title: l10n.settingsTitle,
                        icon: Icons.settings_rounded,
                        onTap: () =>
                            Navigator.pushNamed(context, '/settings'),
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
          children: [
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w500),
              ),
            ),
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
            // Header — bewusst leise, kein Titel-Wettbewerb mit Hero-Feld
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.black87, size: 20),
                    onPressed: () {
                      Haptics.tap();
                      setState(() => _viewState = 'home');
                    },
                  ),
                  const Spacer(),
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
            ),
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
                    // Stage 18: Ambient Coach (immer sichtbar, nie aufdringlich)
                    InlineCoachSection(
                      what: _whatController.text,
                      why: _whyController.text,
                      onChanged: (inj) => setState(
                        () => _ambientCoachInjection = inj.isEmpty ? null : inj,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Erweiterte Suche -> nur sichtbar nach erster Suche
                    if (_hasSearchedOnce) _buildAdvancedExpander(settings),
                    if (_hasSearchedOnce) const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            // Sticky Search-CTA — unten, Daumen-Reichweite
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
                  boxShadow: [
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
                          const SizedBox(width: 10),
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
    if (plz.isEmpty && beruf.isEmpty) {
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
          child: Row(children: const [
            Icon(Icons.info_outline, size: 18, color: Colors.amber),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Stammdaten ergaenzen fuer praezisere Suchen (PLZ, Beruf)',
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 12, color: Colors.black54),
          ]),
        ),
      );
    }
    final parts = <String>[];
    if (plz.isNotEmpty) parts.add('PLZ $plz');
    if (beruf.isNotEmpty) parts.add(beruf);
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
          const SizedBox(width: 8),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.green.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        const Icon(Icons.psychology_alt_outlined,
            size: 16, color: Colors.green),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            adv.summary,
            style: const TextStyle(fontSize: 11, color: Colors.black87),
          ),
        ),
      ]),
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
        boxShadow: [
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
          const SizedBox(width: 14),
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
          children: const [
            Icon(Icons.add_rounded,
                size: 16, color: FindUXProTheme.primaryPurple),
            SizedBox(width: 6),
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
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          Icon(icon,
              color: FindUXProTheme.primaryPurple, size: 20),
          const SizedBox(width: 10),
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
          ),
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
        boxShadow: [
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
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Colors.black54)),
        const SizedBox(height: 8),
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
        children: [
          Container(
            padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top, bottom: 8),
            decoration:
                const BoxDecoration(color: FindUXProTheme.primaryPurple),
            child: Row(
              children: [
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
                          setState(() => _viewState = 'dashboard');
                        },
                ),
                Expanded(
                  child: Text(
                    'Suche: ${_whatController.text}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh,
                      color: Colors.white, size: 22),
                  onPressed: () => _performSearch(),
                  tooltip: 'Im Browser erneut oeffnen',
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
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
                          const SizedBox(height: 24),
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
                                const SizedBox(height: 8),
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
                                setState(() => _viewState = 'dashboard'),
                            icon: const Icon(Icons.tune),
                            label: const Text('Erweiterte Suche'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 30,
                  left: 20,
                  right: 20,
                  child: SafeArea(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
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
                                () => _viewState = 'dashboard'),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() =>
                              _showFeedbackOverlay = !_showFeedbackOverlay),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            decoration: BoxDecoration(
                              color: FindUXProTheme.primaryPurple,
                              borderRadius: BorderRadius.circular(30),
                              boxShadow: [
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
                                const SizedBox(width: 8),
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
                  const SizedBox(height: 24),
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
                  const SizedBox(height: 24),
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
                    if (mandatory) ...[
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
                          children: [
                            Icon(Icons.priority_high_rounded,
                                color: Color(0xFFE53935), size: 16),
                            SizedBox(width: 4),
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
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          alignment: WrapAlignment.center,
                          children: [
                            for (final t in tokenPreview)
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
                            if (extraCount > 0)
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
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildFeedbackIcon(
                            Icons.thumb_down_alt_outlined, 'down', Colors.red),
                        _buildFeedbackIcon(
                            Icons.thumb_up_alt_outlined, 'up', Colors.green),
                      ],
                    ),
                    const SizedBox(height: 24),
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
                    const SizedBox(height: 24),
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
