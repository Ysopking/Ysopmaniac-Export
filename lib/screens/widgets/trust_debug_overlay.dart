import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../logic/query_builder.dart';

/// Debug-Overlay — nur sichtbar wenn kDebugMode == true (d.h. NIE im Release).
///
/// Zeigt nach jeder buildQuery()-Ausfuehrung:
///   • ob der starke Trust-Intent aktiv war
///   • welche Trust-Domains injiziert wurden
///   • Modus, Boost-KWs, Demote-KWs, Learned-Trust, Interests
///   • die fertig gebaute Query (tippen → Clipboard-Kopie)
///
/// Einbindung in home_page.dart via [ValueListenableBuilder] auf
/// [QueryDebugInfo.notifier]. Der Overlay ist zusammenklappbar (Tap auf Header).
class TrustDebugOverlay extends StatefulWidget {
  final QueryDebugInfo info;
  const TrustDebugOverlay({super.key, required this.info});

  @override
  State<TrustDebugOverlay> createState() => _TrustDebugOverlayState();
}

class _TrustDebugOverlayState extends State<TrustDebugOverlay> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    // Doppelte Absicherung: Widget existiert nur wenn kDebugMode
    if (!kDebugMode) return const SizedBox.shrink();

    final info = widget.info;
    final trustColor =
        info.hasStrongTrust ? Colors.greenAccent : Colors.orangeAccent;

    return Positioned(
      right: 8,
      bottom: 80,
      child: Material(
        elevation: 10,
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xEE0D0626),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 310),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header ──────────────────────────────────────────────
                  GestureDetector(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Row(
                      children: [
                        // Status-Indikator
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: trustColor,
                            boxShadow: [
                              BoxShadow(color: trustColor.withOpacity(0.6), blurRadius: 6)
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            info.hasStrongTrust
                                ? 'Trust STARK  (${info.trustDomains.length}D)'
                                : 'Trust normal  (${info.trustDomains.length}D)',
                            style: TextStyle(
                              color: trustColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        // Collapse-Toggle
                        Icon(
                          _expanded ? Icons.expand_less : Icons.expand_more,
                          color: Colors.white38,
                          size: 16,
                        ),
                      ],
                    ),
                  ),

                  // ── Body (kollabierbar) ──────────────────────────────────
                  if (_expanded) ...[
                    const Divider(color: Colors.white12, height: 12),

                    _kv('Mode', info.mode, Colors.cyanAccent),
                    _kvList('Trust-Domains', info.trustDomains, Colors.greenAccent),
                    _kvList('Learned-Trust', info.learnedTrustDomains, Colors.tealAccent),
                    _kvList('Boost-KWs', info.boostKws, Colors.yellowAccent),
                    _kvList('Demote-KWs', info.demoteKws, Colors.redAccent),
                    _kvList('Interests', info.interests, const Color(0xFFCE93D8)),
                    _kvList('SoftTerms', info.softTerms, Colors.white54),
                    _kvList('Excludes', info.excludeDomains, Colors.red.shade200),
                    if (info.dateAfter != null && info.dateAfter!.isNotEmpty)
                      _kv('DateAfter', info.dateAfter!, Colors.lightBlueAccent),
                    if (info.preferIntitle)
                      _kv('Intitle', 'aktiv ✓', Colors.amberAccent),
                    if (info.boostRecent)
                      _kv('BoostRecent', 'aktiv ✓', Colors.amberAccent),

                    const Divider(color: Colors.white12, height: 12),

                    // ── Query-Vorschau (Tap → Clipboard) ─────────────────
                    Tooltip(
                      message: 'Tap → Query in Zwischenablage kopieren',
                      child: GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: info.builtQuery));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Query kopiert'),
                              duration: Duration(seconds: 1),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Text(
                            info.builtQuery.isEmpty
                                ? '(leer)'
                                : info.builtQuery,
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 9.5),
                            maxLines: 5,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _kv(String label, String value, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$label: ',
                style: const TextStyle(color: Colors.white38, fontSize: 10)),
            Flexible(
              child: Text(value,
                  style: TextStyle(color: color, fontSize: 10),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      );

  Widget _kvList(String label, List<String> items, Color color) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ',
              style: const TextStyle(color: Colors.white38, fontSize: 10)),
          Flexible(
            child: Text(
              items.join(', '),
              style: TextStyle(color: color, fontSize: 10),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
