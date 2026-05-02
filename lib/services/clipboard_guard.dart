import 'dart:async';

import 'package:flutter/services.dart';

/// Auto-Clear-Mechanismus fuer die System-Zwischenablage.
///
/// Stage F Haertung: wenn FindUX selbst etwas in die Zwischenablage legt
/// (z.B. eine kopierte Suchanfrage oder ein Feedback-Text), planen wir
/// nach 30 Sekunden ein automatisches Loeschen — aber nur, wenn der
/// Inhalt sich seitdem nicht geaendert hat. So ueberschreiben wir nicht
/// versehentlich Daten, die der User bewusst spaeter eingefuegt hat.
class ClipboardGuard {
  static const Duration _ttl = Duration(seconds: 30);

  Timer? _timer;
  String? _lastSet;

  /// Schreibt [text] in die Zwischenablage und plant das Auto-Clear.
  Future<void> copy(String text) async {
    _timer?.cancel();
    await Clipboard.setData(ClipboardData(text: text));
    _lastSet = text;
    _timer = Timer(_ttl, _clearIfUnchanged);
  }

  Future<void> _clearIfUnchanged() async {
    try {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (current?.text == _lastSet) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    } catch (_) {
      // Best-effort: bei Fehler einfach nichts tun.
    } finally {
      _lastSet = null;
      _timer = null;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _lastSet = null;
  }
}
