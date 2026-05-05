import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../services/chrome_import_service.dart';
import '../services/security_service.dart';
import '../theme.dart';

class ChromeImportScreen extends ConsumerStatefulWidget {
  const ChromeImportScreen({super.key});

  @override
  ConsumerState<ChromeImportScreen> createState() => _ChromeImportScreenState();
}

class _ChromeImportScreenState extends ConsumerState<ChromeImportScreen> {
  bool _busy = false;
  String? _error;
  ImportSummary? _summary;
  int _existingCount = 0;
  List<String> _topDomains = const [];

  @override
  void initState() {
    super.initState();
    _refreshStored();
  }

  Future<Box<dynamic>?> _box() async {
    try {
      final sec = ref.read(securityServiceProvider);
      final key = await sec.getEncryptionKey();
      return await ChromeImportService.openBox(key);
    } catch (e) {
      if (mounted) setState(() => _error = 'Speicher nicht verfuegbar: $e');
      return null;
    }
  }

  Future<void> _refreshStored() async {
    final b = await _box();
    if (b == null || !mounted) return;
    setState(() {
      _existingCount = ChromeImportService.countImported(b);
      _topDomains = ChromeImportService.topImportedDomains(b);
    });
  }

  Future<void> _pickAndAnalyze() async {
    setState(() {
      _busy = true;
      _error = null;
      _summary = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json', 'html', 'htm'],
        withData: false,
      );
      if (result == null || result.files.isEmpty) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final path = result.files.single.path;
      if (path == null) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = 'Pfad nicht zugaenglich.';
          });
        }
        return;
      }

      final sum = await ChromeImportService.analyzeFile(path);
      if (!mounted) return;
      setState(() {
        _summary = sum;
        _busy = false;
      });
      if (sum.tripleCount == 0) {
        setState(() => _error =
            'Keine Such-Eintraege gefunden. Datei wurde trotzdem geloescht.');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Import fehlgeschlagen: $e';
        });
      }
    }
  }

  Future<void> _confirmAndPersist() async {
    final s = _summary;
    if (s == null) return;
    setState(() => _busy = true);
    try {
      final b = await _box();
      if (b == null) return;
      await ChromeImportService.persistAndApply(s.all, b);
      if (!mounted) return;
      setState(() => _summary = null);
      await _refreshStored();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${s.tripleCount} Such-Triples gelernt. Datei wurde geloescht.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Persistieren fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearImported() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Importierten Verlauf loeschen?'),
        content: const Text(
            'Alle reduzierten Such-Triples werden entfernt. Bereits gelernte '
            'Gewichte im Lern-Modell bleiben erhalten.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Loeschen', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final b = await _box();
    if (b == null) return;
    await ChromeImportService.clearImported(b);
    await _refreshStored();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F5F7),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon:
              const Icon(Icons.arrow_back_ios, color: Colors.black, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Verlauf importieren',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
            fontSize: 20,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        children: [
          _privacyCard(),
          const SizedBox(height: 16),
          if (_existingCount > 0) ...[
            _existingCard(),
            const SizedBox(height: 16),
          ],
          if (_summary == null && !_busy) _howToCard(),
          if (_summary != null) _previewCard(),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _errorCard(_error!),
          ],
          const SizedBox(height: 16),
          if (_summary == null && !_busy)
            _bigButton(
              icon: Icons.upload_file_outlined,
              label: 'Datei auswaehlen (.json oder .html)',
              onTap: _pickAndAnalyze,
            ),
          if (_summary != null) ...[
            _bigButton(
              icon: Icons.check_rounded,
              label: 'Lernen & speichern',
              onTap: _busy || _summary!.tripleCount == 0
                  ? null
                  : _confirmAndPersist,
              color: Colors.green.shade700,
            ),
            const SizedBox(height: 8),
            _bigButton(
              icon: Icons.close_rounded,
              label: 'Verwerfen',
              onTap: () => setState(() {
                _summary = null;
                _error = null;
              }),
              color: Colors.grey.shade700,
              outlined: true,
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _privacyCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF1FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: FindUXProTheme.primaryPurple.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined,
              color: FindUXProTheme.primaryPurple, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Was passiert mit der Datei?',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                ),
                const SizedBox(height: 6),
                Text(
                  '1. Die Datei wird lokal gelesen — kein Netzwerk.\n'
                  '2. Pro Suche bleiben nur 4 Felder: Anfrage, Domain, Titel, Wochen-Bucket.\n'
                  '3. Alles andere (Zeitstempel, IDs, Cookies, Detail-Verlauf) wird verworfen.\n'
                  '4. Die Datei wird sofort nach der Reduktion geloescht.',
                  style: TextStyle(
                      color: Colors.black.withValues(alpha: 0.7),
                      fontSize: 12,
                      height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _existingCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history_rounded,
                  color: FindUXProTheme.primaryPurple, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Aktuell gespeichert: $_existingCount Triples',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
              IconButton(
                onPressed: _clearImported,
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                tooltip: 'Importierten Verlauf loeschen',
              ),
            ],
          ),
          if (_topDomains.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Haeufigste Domains:',
                style: TextStyle(
                    color: Colors.black.withValues(alpha: 0.6),
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _topDomains
                  .map((d) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: FindUXProTheme.primaryPurple
                              .withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(d,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.black87)),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _howToCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('So bekommst du eine Verlaufs-Datei:',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
          SizedBox(height: 8),
          Text(
            '• Google Takeout: takeout.google.com -> "Chrome" auswaehlen -> '
            'Export starten -> ZIP entpacken -> "BrowserHistory.json" auf das '
            'Handy uebertragen.\n'
            '• Lesezeichen-Export: in Chrome -> Lesezeichen-Manager -> "..."'
            '-Menue -> "Lesezeichen exportieren" (.html).',
            style: TextStyle(
                color: Colors.black54, fontSize: 12, height: 1.45),
          ),
          SizedBox(height: 8),
          Text(
            'Erkannte Suchmaschinen: Google, Bing, DuckDuckGo, Startpage, '
            'Brave, Ecosia, Qwant, Yahoo, Yandex, Mojeek, MetaGer, Kagi.',
            style: TextStyle(
                color: Colors.black54, fontSize: 11, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _previewCard() {
    final s = _summary!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.summarize_outlined,
                  color: Colors.green, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${s.rawCount} Eintraege gelesen → '
                  '${s.tripleCount} Such-Triples extrahiert',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Datei wurde bereits geloescht. Du entscheidest jetzt, ob die '
            'reduzierten Triples dauerhaft gespeichert (verschluesselt) und '
            'ins Lern-Modell uebernommen werden.',
            style: TextStyle(
                color: Colors.black.withValues(alpha: 0.6),
                fontSize: 11,
                height: 1.4),
          ),
          if (s.samples.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Beispiele:',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            const SizedBox(height: 6),
            ...s.samples.map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F7FB),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('"${t.query}"',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 12)),
                        const SizedBox(height: 2),
                        Text(
                          '${t.domain.isEmpty ? "(kein Klick)" : t.domain} · ${t.week}',
                          style: const TextStyle(
                              color: Colors.black54, fontSize: 11),
                        ),
                        if (t.title.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              t.title,
                              style: const TextStyle(
                                  color: Colors.black54,
                                  fontSize: 10,
                                  fontStyle: FontStyle.italic),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Widget _errorCard(String msg) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(msg, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _bigButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    Color? color,
    bool outlined = false,
  }) {
    final c = color ?? FindUXProTheme.primaryPurple;
    return SizedBox(
      width: double.infinity,
      child: outlined
          ? OutlinedButton.icon(
              onPressed: onTap == null
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      onTap();
                    },
              style: OutlinedButton.styleFrom(
                foregroundColor: c,
                side: BorderSide(color: c),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: Icon(icon, size: 20),
              label: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            )
          : ElevatedButton.icon(
              onPressed: onTap == null
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      onTap();
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: c,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: Icon(icon, size: 20),
              label: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
    );
  }
}
