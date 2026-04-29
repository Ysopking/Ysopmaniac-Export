import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:findux_mobile/l10n/app_localizations.dart';
import '../services/learning_service.dart';
import '../logic/query_builder.dart';
import '../logic/state_provider.dart';
import '../logic/mirror_logic.dart';
import '../logic/deep_analyzer.dart';
import '../theme.dart';

class HomePage extends ConsumerStatefulWidget {
  final LearningService learningService;

  const HomePage({super.key, required this.learningService});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final TextEditingController _whatController = TextEditingController();
  final TextEditingController _whyController = TextEditingController();

  late InAppWebViewController _webViewController;
  late PullToRefreshController _pullToRefreshController;
  bool _webViewLoaded = false;
  bool _showFeedbackOverlay = false;
  bool _showDeepAnalysisOverlay = false;
  List<String> _suggestedGoals = [];
  Timer? _analysisTimer;

  String? _selectedRating;
  final TextEditingController _feedbackController = TextEditingController();

  String _viewState = 'home';

  @override
  void initState() {
    super.initState();
    _pullToRefreshController = PullToRefreshController(
      onRefresh: () async {
        if (Platform.isAndroid) {
          _webViewController.reload();
        } else if (Platform.isIOS) {
          _webViewController.loadUrl(urlRequest: URLRequest(url: await _webViewController.getUrl()));
        }
      },
      settings: PullToRefreshSettings(
        color: FindUXProTheme.secondaryPurple,
      ),
    );
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
    try {
      await InAppWebViewController.clearAllCache();
      final webStorageManager = WebStorageManager.instance();
      await webStorageManager.deleteAllData();
      CookieManager cookieManager = CookieManager.instance();
      await cookieManager.deleteAllCookies();
    } catch (e) {
      debugPrint('Purge Error: $e');
    }
  }

  Future<void> _performSearch({String? addedGoal}) async {
    if (_whatController.text.trim().isEmpty) return;

    await _purgeAllSessionData();

    if (_viewState != 'results') {
      _startDeepAnalysis();
    }

    HapticFeedback.lightImpact();

    final settings = ref.read(settingsProvider);
    final builder = FindUXQueryBuilder();
    final List<String> allFilters = [...settings.sources, ...settings.files];

    final settingsMap = {
      'plz': settings.plz,
      'beruf': settings.beruf,
      'searchengine': settings.searchEngine,
      'enableYouthProtection': settings.enableYouthProtection,
    };

    String contextWhy = _whyController.text;
    if (addedGoal != null) {
      contextWhy = "$contextWhy $addedGoal";
    }

    final fullQuery = await builder.buildQuery(
      what: _whatController.text,
      why: contextWhy,
      filters: allFilters,
      settings: settingsMap,
      mode: settings.mode,
    );

    final url = builder.buildSearchUrl(fullQuery, settings.searchEngine, settingsMap);

    setState(() {
      _viewState = 'results';
      _webViewLoaded = false;
      _currentUrl = url;
      _showDeepAnalysisOverlay = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final randomUA = MirrorLogic.getRandomUserAgent();
      _webViewController.loadUrl(urlRequest: URLRequest(
        url: WebUri(url),
        headers: {
          'User-Agent': randomUA,
          'Accept-Language': 'de-DE,de;q=0.9',
          'Sec-Ch-Ua-Mobile': '?1',
          'Sec-Ch-Ua-Platform': '"iOS"',
          'Sec-Fetch-Mode': 'navigate',
        },
      ));
    });

    widget.learningService.trackSearch(
      query: fullQuery,
      url: url,
      settings: settingsMap,
      sources: settings.sources,
      files: settings.files,
      mode: settings.mode,
    );
  }

  void _startDeepAnalysis() {
    _analysisTimer?.cancel();
    _analysisTimer = Timer(const Duration(seconds: 60), () async {
      if (_viewState == 'results' && mounted) {
        final results = await DeepAnalyzer.analyzeResults(_whatController.text, {});
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
    widget.learningService.trackFeedback(_selectedRating!, comment: _feedbackController.text.trim());
    setState(() {
      _showFeedbackOverlay = false;
      _selectedRating = null;
      _feedbackController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _buildCurrentView(),
    );
  }

  Widget _buildCurrentView() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
            ),
            child: child,
          ),
        );
      },
      child: _getViewForState(),
    );
  }

  Widget _getViewForState() {
    switch (_viewState) {
      case 'home': return _buildPremiumHomeScreen(key: const ValueKey('home'));
      case 'dashboard': return _buildSearchDashboard(key: const ValueKey('dashboard'));
      case 'results': return _buildWebViewResults(key: const ValueKey('results'));
      default: return _buildPremiumHomeScreen(key: const ValueKey('home'));
    }
  }

  Widget _buildPremiumHomeScreen({Key? key}) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      key: key,
      width: double.infinity,
      decoration: const BoxDecoration(gradient: FindUXProTheme.primaryGradient),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const Spacer(flex: 1),
                      Image.asset('assets/logo.png', width: 220, height: 220),
                      const SizedBox(height: 10),
                      Text('FindYouX', style: FindUXProTheme.headlineStyle.copyWith(fontSize: 42, color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: -1)),
                      const Icon(Icons.face_retouching_natural, size: 40, color: Colors.white38),
                      const Spacer(flex: 1),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Column(
                          children: [
                            _buildMenuButton(title: l10n.startSearch, icon: Icons.search_rounded, onTap: () => setState(() => _viewState = 'dashboard')),
                            const SizedBox(height: 16),
                            _buildMenuButton(title: l10n.settingsTitle, icon: Icons.settings_rounded, onTap: () => Navigator.pushNamed(context, '/settings')),
                          ],
                        ),
                      ),
                      const Spacer(flex: 2),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMenuButton({required String title, required IconData icon, required VoidCallback onTap}) {
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
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500),
              ),
            ),
            Icon(icon, color: Colors.white, size: 22),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchDashboard({Key? key}) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      key: key,
      color: FindUXProTheme.primaryPurple,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20), onPressed: () => setState(() => _viewState = 'home')),
                      Text(l10n.knowledgeSession, style: FindUXProTheme.titleStyle.copyWith(color: Colors.white, fontSize: 24)),
                    ],
                  ),
                  const SizedBox(height: 32),
                  _buildMissionInput(controller: _whatController, label: l10n.whatSearch, hint: l10n.topicHint),
                  const SizedBox(height: 20),
                  _buildMissionInput(controller: _whyController, label: l10n.whySearch, hint: l10n.reasonHint),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: FindUXProTheme.primaryButtonStyle.copyWith(
                        backgroundColor: WidgetStateProperty.all(Colors.white),
                        foregroundColor: WidgetStateProperty.all(FindUXProTheme.primaryPurple),
                        padding: WidgetStateProperty.all(const EdgeInsets.symmetric(vertical: 18)),
                      ),
                      onPressed: () => _performSearch(),
                      icon: const Icon(Icons.bolt_rounded),
                      label: Text(l10n.startAnalysis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(color: Color(0xFFF5F5F7), borderRadius: BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30))),
                child: const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: Text('Incognito Mobile Mirror aktiv.\nOptimiert für Handheld-Präzision.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black26, fontSize: 14, fontWeight: FontWeight.w500)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMissionInput({required TextEditingController controller, required String label, required String hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: FindUXProTheme.largeSquircleRadius, border: Border.all(color: Colors.white10)),
          child: TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(color: Colors.white30), border: InputBorder.none),
          ),
        ),
      ],
    );
  }

  Widget _buildWebViewResults({Key? key}) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      key: key,
      children: [
        Container(
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top, bottom: 8),
          decoration: const BoxDecoration(color: FindUXProTheme.primaryPurple),
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 22), onPressed: () async {
                _analysisTimer?.cancel();
                await _purgeAllSessionData();
                _viewState = 'dashboard';
                setState(() {});
              }),
              Expanded(child: Text('Mobile Sandbox: ${_whatController.text}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis)),
              IconButton(icon: const Icon(Icons.refresh, color: Colors.white, size: 22), onPressed: () => _webViewController.reload()),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              RepaintBoundary(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 400),
                  opacity: _webViewLoaded ? 1.0 : 0.0,
                  child: InAppWebView(
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      transparentBackground: true,
                      incognito: true,
                      cacheEnabled: false,
                      clearCache: true,
                      useShouldOverrideUrlLoading: true,
                      safeBrowsingEnabled: true,
                      preferredContentMode: UserPreferredContentMode.MOBILE,
                    ),
                    pullToRefreshController: _pullToRefreshController,
                    onWebViewCreated: (controller) => _webViewController = controller,
                    onLoadStart: (controller, url) {
                      controller.evaluateJavascript(source: MirrorLogic.getStealthShieldJs());
                    },
                    onLoadStop: (controller, url) {
                      setState(() { _webViewLoaded = true; });
                      controller.evaluateJavascript(source: MirrorLogic.getStealthShieldJs());
                    },
                    onProgressChanged: (controller, progress) {
                      if (progress > 30) controller.evaluateJavascript(source: MirrorLogic.getStealthShieldJs());
                    },
                  ),
                ),
              ),
              if (!_webViewLoaded) Container(color: FindUXProTheme.primaryPurple, child: const Center(child: CupertinoActivityIndicator(color: Colors.white, radius: 14))),
              Positioned(bottom: 30, left: 20, right: 20, child: SafeArea(child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: FindUXProTheme.primaryPurple.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(30)), child: Row(children: [
                  IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20), onPressed: () => _webViewController.goBack()),
                  IconButton(icon: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 20), onPressed: () => _webViewController.goForward()),
                ])),
                GestureDetector(onTap: () => setState(() => _showFeedbackOverlay = !_showFeedbackOverlay), child: Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), decoration: BoxDecoration(color: FindUXProTheme.primaryPurple, borderRadius: BorderRadius.circular(30), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 5))]), child: Row(children: [const Icon(Icons.psychology, color: Colors.white, size: 20), const SizedBox(width: 8),                 Text(l10n.learningMode, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))]))),
              ]))),
              if (_showDeepAnalysisOverlay) _buildDeepAnalysisOverlay(),
              if (_showFeedbackOverlay) _buildEnhancedFeedbackOverlay(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDeepAnalysisOverlay() {
    return Positioned.fill(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 500),
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: Container(
              color: Colors.black.withValues(alpha: 0.6 * value),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8 * value, sigmaY: 8 * value),
                child: Center(
                  child: Transform.translate(
                    offset: Offset(0, 50 * (1 - value)),
                    child: child,
                  ),
                ),
              ),
            ),
          );
        },
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: FindUXProTheme.largeSquircleRadius,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome, color: FindUXProTheme.primaryPurple, size: 40),
              const SizedBox(height: 16),
              const Text('Präzisierung nötig', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
              const SizedBox(height: 8),
              const Text(
                'Ich habe die ersten 50 Ergebnisse analysiert. Welches Ziel verfolgst du genau?',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54, fontSize: 14),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _suggestedGoals.map((goal) => GestureDetector(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    _performSearch(addedGoal: goal);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: FindUXProTheme.primaryPurple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: FindUXProTheme.primaryPurple.withValues(alpha: 0.2)),
                    ),
                    child: Text(goal, style: const TextStyle(color: FindUXProTheme.primaryPurple, fontWeight: FontWeight.w600)),
                  ),
                )).toList(),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  setState(() => _showDeepAnalysisOverlay = false);
                },
                child: const Text('Aktuelle Ansicht beibehalten', style: TextStyle(color: Colors.grey)),
              ),
            ],
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
          color: Colors.black.withValues(alpha: 0.4),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Center(
              child: SingleChildScrollView(
                child: Container(
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: FindUXProTheme.largeSquircleRadius,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Spezifizierung präzise?', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                      const SizedBox(height: 12),
                      const Text('Dieses Feedback verfeinert die Gewichtung deiner persönlichen Daten.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54, fontSize: 14)),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildFeedbackIcon(Icons.thumb_down_alt_outlined, 'down', Colors.red),
                          _buildFeedbackIcon(Icons.thumb_up_alt_outlined, 'up', Colors.green),
                        ],
                      ),
                      const SizedBox(height: 24),
                      CupertinoTextField(
                        controller: _feedbackController,
                        placeholder: 'Details zur Sitzung...',
                        maxLines: 3,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: FindUXProTheme.lightGray.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: FindUXProTheme.primaryButtonStyle.copyWith(
                            backgroundColor: WidgetStateProperty.all(_selectedRating != null ? FindUXProTheme.primaryPurple : Colors.grey),
                          ),
                          onPressed: _selectedRating != null ? _submitFeedback : null,
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
      ),
    );
  }

  Widget _buildFeedbackIcon(IconData icon, String rating, Color color) {
    bool isSelected = _selectedRating == rating;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedRating = rating);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : color.withValues(alpha: 0.05),
          shape: BoxShape.circle,
          border: Border.all(color: isSelected ? color : Colors.transparent, width: 2),
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
  __AnimatedScaleButtonState createState() => __AnimatedScaleButtonState();
}

class __AnimatedScaleButtonState extends State<_AnimatedScaleButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
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
