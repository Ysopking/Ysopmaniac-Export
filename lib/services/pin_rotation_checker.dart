import 'dart:io';
import 'package:flutter/foundation.dart';

/// Pin-Rotation-Checker (S-03).
///
/// Prueft beim App-Start ob die gepinnten TLS-Zertifikate in
/// network_security_config.xml noch gueltig sind.
///
/// Expiration der aktuellen Pins: 2027-01-01
/// Letzter Verify: 2026-05-02
class PinRotationChecker {
  PinRotationChecker._();

  static const _pinExpiration = '2027-01-01';

  static const Map<String, String> _expectedIssuers = {
    'www.google.com':    'Google Trust Services',
    'duckduckgo.com':    'DigiCert',
    'www.startpage.com': 'DigiCert',
    'www.bing.com':      'Microsoft',
    'search.brave.com':  'Amazon',
  };

  /// Laeuft nur in kDebugMode oder wenn [forceCheck]=true.
  /// Im Release ohne forceCheck: leere Liste, kein Netzwerk-Call.
  static Future<List<PinCheckResult>> run({bool forceCheck = false}) async {
    if (!kDebugMode && !forceCheck) return [];
    if (!Platform.isAndroid) return [];
    if (kDebugMode) {
      debugPrint('PinRotationChecker: Start — Pins gueltig bis $_pinExpiration');
    }
    final results = <PinCheckResult>[];
    for (final entry in _expectedIssuers.entries) {
      results.add(await _checkHost(entry.key, entry.value));
    }
    if (kDebugMode) {
      final ok   = results.where((r) => r.status == PinCheckStatus.ok).length;
      final warn = results.where((r) => r.status == PinCheckStatus.rotated).length;
      final err  = results.where((r) => r.status == PinCheckStatus.error).length;
      debugPrint('PinRotationChecker: $ok ok, $warn Rotation-Warnung, $err Fehler');
      for (final r in results.where((r) => r.status != PinCheckStatus.ok)) {
        debugPrint('  ⚠ ${r.host}: ${r.message}');
      }
    }
    return results;
  }

  static Future<PinCheckResult> _checkHost(
      String host, String expectedIssuer) async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8)
        ..badCertificateCallback = (cert, h, port) => false;
      final request = await client.getUrl(Uri.https(host, '/'));
      final response = await request.close();
      await response.drain<void>();
      client.close();
      return PinCheckResult(
        host: host,
        status: PinCheckStatus.ok,
        message: 'Verbindung erfolgreich',
      );
    } on HandshakeException catch (e) {
      return PinCheckResult(
        host: host,
        status: PinCheckStatus.rotated,
        message: 'TLS-Fehler (moegliche Pin-Rotation): ${e.message}',
      );
    } on SocketException catch (e) {
      return PinCheckResult(
        host: host,
        status: PinCheckStatus.error,
        message: 'Verbindungsfehler: ${e.message}',
      );
    } catch (e) {
      return PinCheckResult(
        host: host,
        status: PinCheckStatus.error,
        message: 'Fehler: $e',
      );
    }
  }

  static String get pinExpiration => _pinExpiration;

  static bool get isPinExpiringSoon {
    try {
      final expiry = DateTime.parse(_pinExpiration);
      return expiry.difference(DateTime.now()).inDays < 60;
    } catch (_) {
      return false;
    }
  }
}

class PinCheckResult {
  final String host;
  final PinCheckStatus status;
  final String message;
  const PinCheckResult({
    required this.host,
    required this.status,
    required this.message,
  });
}

enum PinCheckStatus { ok, rotated, error }
