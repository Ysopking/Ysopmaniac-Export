import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Sicherheits-Channel zu MainActivity.kt (com.findux/security).
///
/// FLAG_SECURE ist in MainActivity.kt IMMER hart gesetzt — kein Toggle.
/// Diese Klasse verwaltet ausschliesslich den WebView-Screenshot-Workflow:
///
///   1. enterWebView()       — vor InAppWebView-Anzeige aufrufen
///      → FLAG_SECURE wird nativ temporaer aufgehoben
///   2. requestScreenshot()  — vor JEDEM programmatischen Screenshot aufrufen
///      → Rate-Limiter (max 3 / 30 s); gibt true/false zurueck
///   3. exitWebView()        — wenn WebView verlassen wird
///      → FLAG_SECURE sofort wieder hart setzen
///
/// Ausserhalb von InAppWebView sind Screenshots strikt verboten.
/// isSecure() steht als Diagnose-Methode zur Verfuegung.
class SecureFlag {
  static const MethodChannel _channel = MethodChannel('com.findux/security');

  /// Muss BEVOR InAppWebView sichtbar wird aufgerufen werden.
  /// Gibt [true] zurueck wenn der native Code den Flag erfolgreich geoeffnet hat.
  static Future<bool> enterWebView() async {
    try {
      final ok = await _channel.invokeMethod<bool>('enterWebView');
      return ok ?? false;
    } on MissingPluginException {
      return true; // Nicht-Android: kein Flag zu setzen, kein Fehler
    } on PlatformException catch (e) {
      debugPrint('SecureFlag.enterWebView failed: ${e.message}');
      return false;
    }
  }

  /// Muss aufgerufen werden wenn InAppWebView verlassen wird (pop/close).
  /// FLAG_SECURE wird sofort wieder hart gesetzt.
  static Future<void> exitWebView() async {
    try {
      await _channel.invokeMethod<bool>('exitWebView');
    } on MissingPluginException {
      // Nicht-Android: ignorieren
    } on PlatformException catch (e) {
      debugPrint('SecureFlag.exitWebView failed: ${e.message}');
    }
  }

  /// Rate-limitierter Screenshot-Check.
  ///
  /// MUSS vor jedem [InAppWebViewController.takeScreenshot()] aufgerufen werden.
  /// Gibt [true] zurueck wenn noch Tokens verfuegbar (< 3 in den letzten 30 s).
  /// Gibt [false] zurueck wenn das Limit erschoepft ist — Screenshot DARF NICHT
  /// gemacht werden.
  ///
  /// Wirft keine Exception: im Fehlerfall wird [false] zurueckgegeben.
  static Future<bool> requestScreenshot() async {
    try {
      final allowed = await _channel.invokeMethod<bool>('requestScreenshot');
      return allowed ?? false;
    } on MissingPluginException {
      return true; // Nicht-Android: keine Einschraenkung
    } on PlatformException catch (e) {
      debugPrint('SecureFlag.requestScreenshot failed: ${e.message}');
      return false;
    }
  }

  /// Gibt [true] zurueck wenn FLAG_SECURE aktuell gesetzt ist.
  /// Nur fuer Diagnosezwecke gedacht (z.B. Debug-Overlay).
  static Future<bool> isSecure() async {
    try {
      final result = await _channel.invokeMethod<bool>('isSecure');
      return result ?? true;
    } catch (_) {
      return true; // Im Zweifel: Flag angenommen als gesetzt
    }
  }
}
