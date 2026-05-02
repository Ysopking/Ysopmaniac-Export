import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Clipboard-Guard (S-06).
///
/// Problem: Wenn der User eine Suchanfrage kopiert (oder die App intern
/// etwas in die Zwischenablage schreibt), bleibt dieser Text unbegrenzt
/// in der Zwischenablage — andere Apps koennen ihn mitlesen.
///
/// Loesung: Nach [ttl] Sekunden wird die Zwischenablage automatisch
/// geloescht. Fuer Suchanfragen empfehlen wir ttl=30 Sekunden.
///
/// Verwendung:
///   await ClipboardGuard.copyWithTtl('mein suchbegriff');
///   // → kopiert + loesche nach 30s automatisch
class ClipboardGuard {
  ClipboardGuard._();

  static Timer? _clearTimer;
  static const Duration _defaultTtl = Duration(seconds: 30);

  /// Kopiert [text] in die Zwischenablage und plant automatisches Loeschen.
  ///
  /// Falls vorher schon ein Text mit TTL kopiert wurde, wird der alte
  /// Timer abgebrochen und der neue Text bekommt eine frische TTL.
  static Future<void> copyWithTtl(
    String text, {
    Duration ttl = _defaultTtl,
  }) async {
    // Alten Timer abbrechen
    _clearTimer?.cancel();

    await Clipboard.setData(ClipboardData(text: text));
    if (kDebugMode) debugPrint('ClipboardGuard: Text kopiert, TTL=${ttl.inSeconds}s');

    _clearTimer = Timer(ttl, () async {
      try {
        // Nur loeschen wenn der Inhalt noch von uns stammt
        final current = await Clipboard.getData(Clipboard.kTextPlain);
        if (current?.text == text) {
          await Clipboard.setData(const ClipboardData(text: ''));
          if (kDebugMode) debugPrint('ClipboardGuard: Zwischenablage nach TTL geloescht.');
        }
      } catch (e) {
        if (kDebugMode) debugPrint('ClipboardGuard: Loeschen fehlgeschlagen: $e');
      }
      _clearTimer = null;
    });
  }

  /// Loescht die Zwischenablage sofort und bricht laufende Timer ab.
  static Future<void> clearNow() async {
    _clearTimer?.cancel();
    _clearTimer = null;
    try {
      await Clipboard.setData(const ClipboardData(text: ''));
    } catch (_) {}
  }

  /// Muss aufgerufen werden wenn die App in den Hintergrund geht
  /// (z.B. in AutoLockObserver.onPaused) um keine Daten stehen zu lassen.
  static void cancelTimer() {
    _clearTimer?.cancel();
    _clearTimer = null;
  }
}
