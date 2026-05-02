import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// TLS-Wächter für den FindUX In-App-Browser (WebView).
///
/// Hintergrund:
///   network_security_config.xml schützt native HTTP-Calls (OkHttp etc.)
///   via <pin-set>. WebView respektiert die <trust-anchors>-Policy (kein
///   User-CA), aber NICHT die <pin-set>-Pins.
///   TlsGuard schliesst diese Lücke: Er validiert die Issuer-Organisation
///   des Server-Zertifikats fuer alle bekannten Such-Engine-Hosts.
///
/// Angriffsszenario das abgewehrt wird:
///   • Angreifer installiert eine eigene CA nicht auf dem Gerät (das blockiert
///     bereits network_security_config), sondern bringt das Gerät dazu, einer
///     kompromittierten Intermediate-CA zu vertrauen (z.B. durch Root-Exploit).
///   • TlsGuard erkennt: "Der Aussteller des Zertifikats für google.com ist
///     nicht Google Trust Services" → Verbindung wird getrennt.
///
/// Einschränkung:
///   Der Check basiert auf dem O-Feld (Organization) des Zertifikat-Issuers.
///   Ein hochentwickelter Angreifer mit Zugriff auf eine legitimate CA
///   (z.B. gestohlener DigiCert-Signing-Key) wird NICHT erkannt.
///   Für diesen Angriff ist SPKI-Pinning nötig (erfordert ASN.1-Parsing,
///   separates Paket). Der aktuelle Schutz deckt die praktisch relevanten
///   MITM-Szenarien ab.
///
/// Verwendung in incognito_browser_screen.dart:
///   onReceivedServerTrustAuthRequest: (c, challenge) async {
///     return TlsGuard.evaluate(challenge);
///   },
class TlsGuard {
  TlsGuard._();

  /// Host → akzeptierte CA-Organisationsname-Fragmente (Substring-Match).
  /// Mehrere Einträge erlauben CA-Rotation innerhalb derselben CA-Familie.
  static const Map<String, List<String>> _allowedCaOrgs = {
    // Google Trust Services LLC / Google Trust Services (WE1, WE2, etc.)
    'www.google.com':     ['Google Trust Services'],
    'scholar.google.com': ['Google Trust Services'],
    // Microsoft Corporation (eigene PKI)
    'www.bing.com':       ['Microsoft'],
    // DigiCert Inc / GeoTrust (DigiCert-Tochter)
    'duckduckgo.com':     ['DigiCert'],
    'www.startpage.com':  ['DigiCert'],
    // Amazon Trust Services
    'search.brave.com':   ['Amazon'],
  };

  /// Evaluiert eine ServerTrust-Herausforderung und gibt eine Antwort zurück.
  ///
  /// Gibt [ServerTrustAuthResponse(CANCEL)] zurück wenn ein MITM-Verdacht
  /// festgestellt wird (falscher CA-Aussteller für bekannten Host).
  /// Gibt [null] zurück für alle anderen Fälle — die normale System-
  /// Zertifikats-Validierung läuft dann weiter (sicherster Default).
  static Future<ServerTrustAuthResponse?> evaluate(
    URLAuthenticationChallenge challenge,
  ) async {
    final host = challenge.protectionSpace.host;
    final cert = challenge.protectionSpace.sslCertificate;

    final allowedOrgs = _allowedCaOrgs[host];
    if (allowedOrgs == null) {
      // Kein bekannter Such-Engine-Host → System-Validierung entscheiden lassen
      return null;
    }

    if (cert == null) {
      // Kein Zertifikat bei bekanntem Host → MITM-Indiz, Verbindung trennen
      debugPrint('TlsGuard: Kein Zertifikat für $host — Verbindung getrennt.');
      return ServerTrustAuthResponse(
        action: ServerTrustAuthResponseAction.CANCEL,
      );
    }

    final issuerOrg = cert.issuedBy?.oName ?? '';

    final isKnown = allowedOrgs.any(
      (org) => issuerOrg.contains(org),
    );

    if (!isKnown) {
      // MITM-Verdacht: CA-Aussteller nicht in der bekannten Liste
      debugPrint(
        'TlsGuard: ⚠️ MITM-Verdacht!\n'
        '  Host:     $host\n'
        '  Aussteller: "$issuerOrg"\n'
        '  Erwartet:   ${allowedOrgs.join(" | ")}\n'
        '  → Verbindung getrennt.',
      );
      return ServerTrustAuthResponse(
        action: ServerTrustAuthResponseAction.CANCEL,
      );
    }

    // CA-Aussteller bekannt → System-Validierung entscheiden lassen
    // WICHTIG: Wir geben NICHT PROCEED zurück (das würde System-Validation
    // überspringen). null → System-Check läuft normal weiter.
    debugPrint('TlsGuard: ✓ $host — Aussteller "$issuerOrg" akzeptiert.');
    return null;
  }
}
