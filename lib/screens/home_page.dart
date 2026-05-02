import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:findux_mobile/l10n/app_localizations.dart';
import '../services/learning_service.dart';
import '../logic/query_builder.dart';
import '../logic/state_provider.dart';
import '../logic/deep_analyzer.dart';
import '../theme.dart';
import '../coach/coach_models.dart';
import '../coach/coach_screen.dart';
import '../coach/vagueness_detector.dart';
import '../coach/theme_detector.dart';
import '../coach/precision_advisor.dart';

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
  List<String> _suggestedGoals = [];
  Timer? _analysisTimer;

  String? _selectedRating;
  final TextEditingController _feedbackController = TextEditingController();

  String _viewState = 'home';
  PrecisionRecommendation? _advice;

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
  }

  Future<void> _loadAdvice() async {
    final r = await PrecisionAdvisor.analyze();
    if (mounted) setState(() => _advice = r);
  }

  @override
  void dispose() {
    _analysisTimer?.cancel();
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
    });
  }

  Future<void> _performSearch({
    String? addedGoal,
    CoachInjection? injection,
    String? overrideQuery,
    List<Map<String, dynamic>>? coachChoices,
  }) async {
    if (_whatController.text.trim().isEmpty) return;

    // Coach-Trigger nur bei initialer User-Suche (nicht bei Recoach/AddedGoal)
    if (injection == null && overrideQuery == null && addedGoal == null) {
      final what = _whatController.text;
      final why = _whyController.text;
      if (VaguenessDetector.isVague(what: what, why: why)) {
        final theme = ThemeDetector.detect(what, why);
        final s = ref.read(settingsProvider);
        final adv = _advice;
        final initialMode = (adv != null && adv.hasData)
            ? adv.preferredMode
            : s.mode;
        if (!mounted) return;
        final result = await Navigator.push<CoachResult>(
          context,
          MaterialPageRoute(
            builder: (_) => CoachScreen(
              initialTheme: theme,
              what: what,
              why: why,
              currentMode: initialMode,
              currentSources: s.sources,
              currentFiles: s.files,
            ),
          ),
        );
        if (result == null) return; // User hat Coach abgebrochen
        if (!result.skipped) {
          injection = CoachInjection.fromChoices(result.choices);
          overrideQuery = result.overrideQuery;
          coachChoices =
              result.choices.map((c) => c.toJson()).toList();
        }
      }
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
      'searchengine': settings.searchEngine,
      'enableYouthProtection': settings.enableYouthProtection,
      'language': settings.language,
      'country': settings.country,
    };

    String contextWhy = _whyController.text;
    if (addedGoal != null) {
      contextWhy = '$contextWhy $addedGoal';
    }

    final effectiveMode = injection?.modeOverride ?? settings.mode;
    final fullQuery = overrideQuery ??
        await builder.buildQuery(
          what: _whatController.text,
          why: contextWhy,
          filters: allFilters,
          settings: settingsMap,
          mode: effectiveMode,
          coachInjection: injection,
        );

    final url = builder.buildSearchUrl(
        fullQuery, settings.searchEngine, settingsMap);

    setState(() {
      _viewState = 'results';
      _showDeepAnalysisOverlay = false;
      _hasSearchedOnce = true;
    });

    final uri = Uri.tryParse(url);
    if (uri != null) {
      try {
        bool ok = false;
        if (settings.openInApp) {
          ok = await launchUrl(
            uri,
            mode: LaunchMode.inAppBrowserView,
            browserConfiguration:
                const BrowserConfiguration(showTitle: true),
          );
        }
        if (!ok) {
          ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        if (!ok && mounted) _showLaunchFailedSnack();
      } catch (e) {
        debugPrint('launchUrl error: $e');
        if (mounted) _showLaunchFailedSnack();
      }
    }

    await widget.learningService.trackSearch(
      query: fullQuery,
      url: url,
      settings: settingsMap,
      sources: settings.sources,
      files: settings.files,
      mode: effectiveMode,
      coachChoices: coachChoices,
    );

    // Stil-Analyzer nach jeder Suche neu laden (asynchron, blockiert nichts)
    // ignore: discarded_futures
    PrecisionAdvisor.analyze().then((rec) {
      if (mounted) setState(() => _advice = rec);
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

  void _submitFeedback() {
    if (_selectedRating == null) return;
    HapticFeedback.mediumImpact();
    widget.learningService.trackFeedback(_selectedRating!,
        comment: _feedbackController.text.trim());
    setState(() {
      _showFeedbackOverlay = false;
      _selectedRating = null;
      _feedbackController.clear();
    });
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _getViewForState(),
      ),
    );
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

  // ---------- Search Dashboard (Light, Card-Style) ----------

  Widget _buildSearchDashboard({Key? key}) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(settingsProvider);
    return Container(
      key: key,
      color: const Color(0xFFF5F5F7),
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios,
                        color: Colors.black87, size: 20),
                    onPressed: () => setState(() => _viewState = 'home'),
                  ),
                  Expanded(
                    child: Text(l10n.knowledgeSession,
                        style: const TextStyle(
                            color: Colors.black,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined,
                        color: Colors.black54),
                    onPressed: () =>
                        Navigator.pushNamed(context, '/settings'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStammdatenPill(),
                    _buildAdvicePill(),
                    _buildLightInput(
                      controller: _whatController,
                      label: l10n.whatSearch,
                      hint: l10n.topicHint,
                      icon: Icons.search,
                    ),
                    const SizedBox(height: 14),
                    _buildLightInput(
                      controller: _whyController,
                      label: l10n.whySearch,
                      hint: l10n.reasonHint,
                      icon: Icons.psychology_outlined,
                    ),
                    const SizedBox(height: 20),

                    // Erweiterte Suche -> nur sichtbar nach erster Suche
                    if (_hasSearchedOnce) _buildAdvancedExpander(settings),
                    if (_hasSearchedOnce) const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: FindUXProTheme.primaryPurple,
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        onPressed: () => _performSearch(),
                        icon: const Icon(Icons.bolt_rounded),
                        label: Text(l10n.startAnalysis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 17)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _hasSearchedOnce
                          ? 'Tipp: oeffne "Erweiterte Suche" um Quellen, Dateitypen und den Such-Modus zu verfeinern.'
                          : 'Nach deiner ersten Suche kannst du Quellen, Dateitypen und Modus verfeinern.',
                      style: const TextStyle(
                          color: Colors.black54, fontSize: 12),
                    ),
                  ],
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

  Widget _buildLightInput({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: FindUXProTheme.primaryPurple, size: 18),
              const SizedBox(width: 8),
              Text(label,
                  style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            style: const TextStyle(
                color: Colors.black87,
                fontSize: 16,
                fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.black26),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 6),
            ),
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
                  icon:
                      const Icon(Icons.close, color: Colors.white, size: 22),
                  onPressed: () async {
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
    return Positioned.fill(
      child: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
          setState(() => _showFeedbackOverlay = false);
        },
        child: Container(
          color: Colors.black45,
          child: Center(
            child: SingleChildScrollView(
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Spezifizierung praezise?',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 20)),
                    const SizedBox(height: 12),
                    const Text(
                        'Dieses Feedback verfeinert die Gewichtung deiner persoenlichen Daten.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.black54, fontSize: 14)),
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
                      placeholder: 'Details zur Sitzung...',
                      maxLines: 3,
                      padding: const EdgeInsets.all(12),
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
                        child: const Text('Sitzung bewerten'),
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
