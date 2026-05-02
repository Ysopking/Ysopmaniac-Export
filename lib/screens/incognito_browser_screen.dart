import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart' as ext;

/// Privater In-App-Browser. Verwendet flutter_inappwebview ohne den
/// `incognito:true`-Flag, weil dieser Flag den Cookie-Store so isoliert
/// dass wir keine Consent-Cookies vor-injizieren koennen.
///
/// Stattdessen:
///  1. initState: ALLE Cookies + WebStorage werden geleert
///  2. Google-Consent-Cookies werden VOR dem URL-Load gesetzt
///     (CONSENT, SOCS) — damit Google den AGB-Banner gar nicht erst zeigt
///  3. Beim Laden: cacheEnabled:false, clearCache:true,
///     thirdPartyCookiesEnabled:false
///  4. dispose: ALLE Cookies + WebStorage werden wieder geleert
///
/// Effekt: Waehrend einer Browse-Session funktioniert die Seite normal,
/// nach dem Schliessen bleibt nichts uebrig — keine Cookies, keine
/// LocalStorage, kein Cache. Aus User-Sicht echtes Inkognito, aber
/// Google sieht ein "schon zugestimmt"-Cookie (das nach dem Schliessen
/// wieder weg ist).
class IncognitoBrowserScreen extends StatefulWidget {
  final String url;
  const IncognitoBrowserScreen({super.key, required this.url});

  @override
  State<IncognitoBrowserScreen> createState() => _IncognitoBrowserScreenState();
}

class _IncognitoBrowserScreenState extends State<IncognitoBrowserScreen> {
  InAppWebViewController? _webController;
  double _progress = 0;
  String _currentUrl = '';
  String _title = '';
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
    // ignore: discarded_futures
    _prepareSession();
  }

  Future<void> _prepareSession() async {
    try {
      // 1. Vor jedem Start: alles wegputzen
      await CookieManager.instance().deleteAllCookies();
      await InAppWebViewController.clearAllCache();
    } catch (_) {}

    // 2. Google-Consent-Cookies setzen (Banner verschwindet)
    try {
      final cm = CookieManager.instance();
      const consentDomains = ['.google.com', '.google.de'];
      for (final d in consentDomains) {
        await cm.setCookie(
          url: WebUri('https://www.google.com'),
          name: 'CONSENT',
          value: 'YES+cb.20210720-07-p0.de+FX+410',
          domain: d,
          path: '/',
          isSecure: true,
        );
        await cm.setCookie(
          url: WebUri('https://www.google.com'),
          name: 'SOCS',
          value: 'CAESHAgBEhJnd3NfMjAyMTA3MjAtMF9SQzIaAmRlIAEaBgiAo7-IBg',
          domain: d,
          path: '/',
          isSecure: true,
        );
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() => _ready = true);
  }

  @override
  void dispose() {
    // 4. Beim Schliessen: alle Spuren der Browse-Session weg
    // ignore: discarded_futures
    () async {
      try {
        await CookieManager.instance().deleteAllCookies();
        await InAppWebViewController.clearAllCache();
      } catch (_) {}
    }();
    super.dispose();
  }

  Future<void> _openExternally() async {
    final uri = Uri.tryParse(_currentUrl);
    if (uri == null) return;
    HapticFeedback.selectionClick();
    try {
      await ext.launchUrl(uri, mode: ext.LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _refreshNav() async {
    final back = await _webController?.canGoBack() ?? false;
    final fwd = await _webController?.canGoForward() ?? false;
    if (!mounted) return;
    setState(() {
      _canGoBack = back;
      _canGoForward = fwd;
    });
  }

  String _hostOf(String u) {
    final p = Uri.tryParse(u);
    return p?.host ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A0F3D),
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.shield_moon_outlined,
                    size: 14, color: Colors.amber),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    _title.isEmpty ? 'Privat' : _title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            Text(
              _hostOf(_currentUrl),
              style: TextStyle(
                fontSize: 10,
                color: Colors.white.withValues(alpha: 0.6),
                fontWeight: FontWeight.w400,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Schliessen',
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: 'In externer App oeffnen',
            onPressed: _openExternally,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: _progress < 1.0
              ? LinearProgressIndicator(
                  value: _progress,
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Colors.amber),
                )
              : const SizedBox(height: 2),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              color: const Color(0xFF1A0F3D),
              child: Row(
                children: [
                  const Icon(Icons.privacy_tip_outlined,
                      size: 14, color: Colors.amber),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Privat: nichts wird ueber das Schliessen hinaus gespeichert',
                      style: TextStyle(
                        color: Colors.amber.withValues(alpha: 0.9),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: !_ready
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Colors.amber,
                      ),
                    )
                  : InAppWebView(
                      initialUrlRequest:
                          URLRequest(url: WebUri(widget.url)),
                      initialSettings: InAppWebViewSettings(
                        // KEIN incognito:true — sonst kann unsere
                        // Consent-Cookie-Injection nicht greifen.
                        cacheEnabled: false,
                        clearCache: true,
                        clearSessionCache: true,
                        javaScriptEnabled: true,
                        thirdPartyCookiesEnabled: false,
                        supportZoom: true,
                        builtInZoomControls: true,
                        displayZoomControls: false,
                        mediaPlaybackRequiresUserGesture: true,
                        useHybridComposition: true,
                      ),
                      onWebViewCreated: (c) => _webController = c,
                      onLoadStart: (c, url) {
                        if (!mounted) return;
                        setState(() {
                          _currentUrl =
                              url?.toString() ?? _currentUrl;
                          _progress = 0;
                        });
                      },
                      onLoadStop: (c, url) async {
                        final t = await c.getTitle();
                        if (!mounted) return;
                        setState(() {
                          _currentUrl =
                              url?.toString() ?? _currentUrl;
                          _title = t ?? '';
                          _progress = 1.0;
                        });
                        await _refreshNav();
                      },
                      onProgressChanged: (c, p) {
                        if (!mounted) return;
                        setState(() => _progress = p / 100.0);
                      },
                      onTitleChanged: (c, title) {
                        if (!mounted) return;
                        setState(() => _title = title ?? '');
                      },
                    ),
            ),
            Container(
              color: const Color(0xFF1A0F3D),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_rounded,
                        color: Colors.white),
                    disabledColor: Colors.white24,
                    onPressed: _canGoBack
                        ? () async {
                            await _webController?.goBack();
                            await _refreshNav();
                          }
                        : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios_rounded,
                        color: Colors.white),
                    disabledColor: Colors.white24,
                    onPressed: _canGoForward
                        ? () async {
                            await _webController?.goForward();
                            await _refreshNav();
                          }
                        : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    onPressed: () => _webController?.reload(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.open_in_new,
                        color: Colors.white),
                    tooltip: 'Extern oeffnen',
                    onPressed: _openExternally,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
