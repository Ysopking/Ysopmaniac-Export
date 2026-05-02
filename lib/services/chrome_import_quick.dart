import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'chrome_import_service.dart';
import 'haptic_helper.dart';
import 'security_service.dart';

/// Geführter Chrome-Verlauf-Import (Stage G — Apple-UX).
///
/// Frueher: ein Tap -> File-Picker -> ... aber 90 % der User haben gar
/// keine Verlaufs-Datei zur Hand und brechen ab.
///
/// Jetzt: ein Tap oeffnet ein Bottom-Sheet mit drei nummerierten
/// Schritten und ZWEI klaren Pfaden:
///   1) "Zu Google Takeout"  -> oeffnet die richtige Takeout-URL im
///      Browser, das Sheet bleibt offen.
///   2) Sobald der User von Takeout zurueckkehrt, schaltet das Sheet
///      automatisch auf den prominenten Knopf "Datei jetzt waehlen".
///
/// Rueckgabe: true = mind. ein Triple importiert; false = abgebrochen.
const String kTakeoutUrl =
    'https://takeout.google.com/settings/takeout/custom/chrome';

Future<bool> quickImportChrome(BuildContext context) async {
  Haptics.tap();
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => const _ImportGuideSheet(),
  );
  return result ?? false;
}

class _ImportGuideSheet extends StatefulWidget {
  const _ImportGuideSheet();

  @override
  State<_ImportGuideSheet> createState() => _ImportGuideSheetState();
}

class _ImportGuideSheetState extends State<_ImportGuideSheet> {
  bool _takeoutOpened = false;
  bool _busy = false;

  Future<void> _openTakeout() async {
    if (_busy) return;
    Haptics.tap();
    final ok = await launchUrl(
      Uri.parse(kTakeoutUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!mounted) return;
    if (ok) {
      setState(() => _takeoutOpened = true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Konnte Google Takeout nicht oeffnen.'),
        backgroundColor: Colors.red.shade700,
      ));
    }
  }

  Future<void> _pickAndImport() async {
    if (_busy) return;
    setState(() => _busy = true);
    Haptics.tap();

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json', 'html', 'htm', 'zip'],
        withData: false,
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Datei-Auswahl fehlgeschlagen: $e'),
        backgroundColor: Colors.red.shade700,
      ));
      setState(() => _busy = false);
      return;
    }

    if (picked == null || picked.files.isEmpty) {
      if (mounted) setState(() => _busy = false);
      return;
    }

    final path = picked.files.single.path;
    if (path == null) {
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
        content: Text('Pfad nicht zugaenglich.'),
        backgroundColor: Colors.red,
      ));
      setState(() => _busy = false);
      return;
    }

    messenger.showSnackBar(const SnackBar(
      duration: Duration(seconds: 3),
      content: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Colors.white),
          ),
          SizedBox(width: 12),
          Expanded(child: Text('Verlauf wird lokal reduziert ...')),
        ],
      ),
    ));

    try {
      final summary = await ChromeImportService.analyzeFile(path);

      if (summary.tripleCount == 0) {
        if (!mounted) return;
        messenger.showSnackBar(SnackBar(
          content: const Text(
              'Keine Such-Eintraege gefunden. Datei wurde dennoch geloescht.'),
          backgroundColor: Colors.orange.shade800,
        ));
        navigator.pop(false);
        return;
      }

      final security = SecurityService();
      final key = await security.getEncryptionKey();
      final box = await ChromeImportService.openBox(key);
      await ChromeImportService.persistAndApply(summary.all, box);

      // D1: Zweiter Lern-Pass — Top-Domains als URL-Pfad-Tokens bumpen.
      // applyInterestBumps() tokenisiert die Domain-Strings (z.B. "apotheken-umschau.de"
      // → ["apotheken", "umschau"]) und bumpt die entsprechenden weight_kw_*-Keys.
      final topDomains = ChromeImportService.topImportedDomains(box, limit: 10);
      if (topDomains.isNotEmpty) {
        await ChromeImportService.applyInterestBumps(topDomains);
      }

      if (!mounted) return;
      Haptics.done();
      messenger.showSnackBar(SnackBar(
        content: Text(
            '${summary.tripleCount} Such-Triples gelernt. Datei geloescht.'),
        backgroundColor: Colors.green.shade700,
      ));
      navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('Import fehlgeschlagen: $e'),
        backgroundColor: Colors.red.shade700,
      ));
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF5F5F7),
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Drag-Handle (iOS-Stil)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Container(
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                children: [
                  const Text(
                    'Verlauf importieren',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'In drei Schritten holst du dir deinen Chrome-Verlauf '
                    'aus Google Takeout. Alles bleibt verschluesselt auf '
                    'deinem Geraet.',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.4,
                      color: Colors.black.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _step(
                    n: 1,
                    title: 'Bei Google Takeout anmelden',
                    body: 'Tippe unten auf "Zu Google Takeout". '
                        'Du wirst direkt zur Chrome-Auswahl gefuehrt — '
                        'andere Daten sind bereits abgewaehlt.',
                  ),
                  const SizedBox(height: 14),
                  _step(
                    n: 2,
                    title: 'Nur "Chrome" auswaehlen, Format JSON',
                    body: 'Im Takeout-Bildschirm: stell sicher, dass nur '
                        'der Eintrag "Chrome" angehakt ist. Klicke darauf '
                        'und waehle "JSON" als Datei-Format. Tippe dann '
                        'auf "Naechster Schritt" und "Export erstellen".',
                  ),
                  const SizedBox(height: 14),
                  _step(
                    n: 3,
                    title: 'Datei herunterladen & hier waehlen',
                    body: 'Google sendet dir eine ZIP. Lade sie herunter '
                        '(oder entpacke sie und nimm die Datei "History.json"). '
                        'Tippe danach unten auf "Datei jetzt waehlen".',
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: Colors.green.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.lock_outline_rounded,
                            size: 20, color: Colors.green),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'FindUX reduziert die Datei lokal auf vier Felder '
                            '(Query, Domain, Titel, Wochenbucket) und loescht '
                            'die Originaldatei sofort. Nichts verlaesst '
                            'dein Geraet.',
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: Colors.black.withValues(alpha: 0.75),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
            // Action-Bar (sticky unten)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Column(
                  children: [
                    if (!_takeoutOpened) ...[
                      _heroButton(
                        label: 'Zu Google Takeout',
                        icon: Icons.open_in_new_rounded,
                        onTap: _openTakeout,
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _busy ? null : _pickAndImport,
                        style: TextButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                          foregroundColor: Colors.black54,
                        ),
                        child: const Text(
                          'Ich habe schon eine Datei',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ] else ...[
                      _heroButton(
                        label: _busy
                            ? 'Datei wird verarbeitet ...'
                            : 'Datei jetzt waehlen',
                        icon: Icons.folder_open_rounded,
                        onTap: _busy ? null : _pickAndImport,
                        busy: _busy,
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _busy ? null : _openTakeout,
                        style: TextButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                          foregroundColor: Colors.black54,
                        ),
                        icon: const Icon(Icons.open_in_new_rounded,
                            size: 16),
                        label: const Text(
                          'Erneut zu Google Takeout',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _step({required int n, required String title, required String body}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xFF2E1A47),
            shape: BoxShape.circle,
          ),
          child: Text('$n',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              )),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: Colors.black.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _heroButton({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
    bool busy = false,
  }) {
    const purple = Color(0xFF2E1A47);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: purple,
        borderRadius: BorderRadius.circular(20),
        boxShadow: onTap == null
            ? []
            : [
                BoxShadow(
                  color: purple.withValues(alpha: 0.30),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                else
                  Icon(icon, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
