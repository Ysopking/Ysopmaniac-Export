import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'chrome_import_service.dart';
import 'security_service.dart';

/// Ein-Klick-Import des Chrome-Verlaufs ohne Zwischen-Screen.
///
/// Ablauf in einem einzigen User-Tap:
///   1. File-Picker oeffnet sich direkt
///   2. Datei wird lokal analysiert (Limits: 50 MB Datei, 200k Eintraege)
///   3. Triples werden sofort verschluesselt persistiert + ins Lern-Modell
///      uebernommen
///   4. SnackBar meldet Ergebnis. Original-Datei wird in jedem Fall geloescht.
///
/// Rueckgabe: true wenn mindestens ein Triple importiert wurde, sonst false
/// (Abbruch durch User oder leere Datei). Damit kann z.B. das Onboarding
/// den "fertig"-Haken setzen.
///
/// Hinweis zum SecurityService: wir instanziieren ihn lokal, weil der
/// eigentliche Encryption-Key in flutter_secure_storage liegt — die
/// Service-Instanz ist nur ein duenner Wrapper darum. Damit bleibt
/// der Helper unabhaengig von Riverpod-Overrides.
Future<bool> quickImportChrome(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  HapticFeedback.selectionClick();

  // 1. Datei-Picker
  FilePickerResult? picked;
  try {
    picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json', 'html', 'htm'],
      withData: false,
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(
      content: Text('Datei-Auswahl fehlgeschlagen: $e'),
      backgroundColor: Colors.red.shade700,
    ));
    return false;
  }

  if (picked == null || picked.files.isEmpty) {
    return false; // User hat abgebrochen — keine SnackBar noetig.
  }

  final path = picked.files.single.path;
  if (path == null) {
    messenger.showSnackBar(const SnackBar(
      content: Text('Pfad nicht zugaenglich.'),
      backgroundColor: Colors.red,
    ));
    return false;
  }

  // 2. Fortschritts-Anzeige (nicht blockierend)
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
    // 3. Analyze (loescht Original-Datei intern)
    final summary = await ChromeImportService.analyzeFile(path);

    if (summary.tripleCount == 0) {
      messenger.showSnackBar(SnackBar(
        content: const Text(
            'Keine Such-Eintraege gefunden. Datei wurde dennoch geloescht.'),
        backgroundColor: Colors.orange.shade800,
      ));
      return false;
    }

    // 4. Persist (verschluesselter Vault + milde Lern-Bumps)
    final security = SecurityService();
    final key = await security.getEncryptionKey();
    final box = await ChromeImportService.openBox(key);
    await ChromeImportService.persistAndApply(summary.all, box);

    messenger.showSnackBar(SnackBar(
      content: Text(
          '${summary.tripleCount} Such-Triples gelernt. Datei geloescht.'),
      backgroundColor: Colors.green.shade700,
    ));
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(
      content: Text('Import fehlgeschlagen: $e'),
      backgroundColor: Colors.red.shade700,
    ));
    return false;
  }
}
