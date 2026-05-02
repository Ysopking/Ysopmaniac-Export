import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart' as ext;

/// Eingebauter Inkognito-Browser. Verwendet flutter_inappwebview mit
/// incognito:true, d.h. der WebView nutzt eine private BrowserContext-
/// Instanz: keine Cookies, kein Cache, keine LocalStorage-Persistenz,
/// kein History-Eintrag. Wird beim Schliessen automatisch verworfen.
///
/// Bewusst kein url_launcher mit LaunchMode.inAppBrowserView (Android
/// Custom Tabs), weil Custom Tabs Cookies/Login mit dem Default-Browser
/// teilen — das widerspricht der Zero-Tracking-Garantie.
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

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
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
                    _title.isEmpty ? 'Inkognito' : _title,
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
                      'Inkognito: keine Cookies, kein Cache, keine Speicherung',
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
              child: InAppWebView(
                initialUrlRequest:
                    URLRequest(url: WebUri(widget.url)),
                initialSettings: InAppWebViewSettings(
                  incognito: true,
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
                    _currentUrl = url?.toString() ?? _currentUrl;
                    _progress = 0;
                  });
                },
                onLoadStop: (c, url) async {
                  final t = await c.getTitle();
                  if (!mounted) return;
                  setState(() {
                    _currentUrl = url?.toString() ?? _currentUrl;
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
