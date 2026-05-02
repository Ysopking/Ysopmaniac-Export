# FindUX Security Policy

## Vulnerability Disclosure

Sicherheitslücken bitte **nicht** als öffentliches GitHub-Issue melden.

Stattdessen: E-Mail an das Entwicklungsteam (Betreff: `[SECURITY] FindUX`).
Wir bestätigen den Eingang innerhalb von **72 Stunden** und liefern eine
erste Einschätzung innerhalb von **7 Tagen**.

---

## Unterstützte Versionen

| Version | Support |
|---------|---------|
| neueste Release | ✅ aktiv |
| ältere Releases | ❌ kein Patch |

---

## Sicherheitsarchitektur

### Datenspeicherung
- **Hive AES-256-Verschlüsselung**: Alle Suchanfragen, Verlauf und Präferenzen
  werden mit einem AES-256-CBC-Schlüssel verschlüsselt, der im
  Android Keystore (Hardware-backed ab API 23) gespeichert ist.
- **Keine Cloud-Synchronisation**: Alle Daten verbleiben auf dem Gerät.
- **Session-Schutz**: Der Encryption-Key wird beim Sperren der App aus
  dem RAM gelöscht (`clearCachedKey()`). Die Hive-Box wird geschlossen
  (`closeBox()`). Re-Aktivierung erfordert Biometrie.

### Netzwerk
- **Certificate Pinning**: 3-Schichten-Ansatz:
  1. `network_security_config.xml` — SPKI-Pins für alle Suchmaschinen
  2. `TlsGuard` — WebView `onReceivedServerTrustAuthRequest`
  3. `TlsGuard` — HTTP-Client `badCertificateCallback`
- **Kein HTTP**: `cleartextTrafficPermitted="false"` für alle Verbindungen.

### Zertifikat-Pins (aktuell)
| Host | Erwarteter Issuer | Gültig bis |
|------|-------------------|------------|
| www.google.com | Google Trust Services | 2027-01-01 |
| duckduckgo.com | DigiCert | 2027-01-01 |
| www.startpage.com | DigiCert | 2027-01-01 |
| www.bing.com | Microsoft | 2027-01-01 |
| search.brave.com | Amazon | 2027-01-01 |

**Pin-Rotation**: Bei einem Issuer-Wechsel muss `network_security_config.xml`
sowie `TlsGuard.kt` aktualisiert werden. `PinRotationChecker.dart` warnt
automatisch 60 Tage vor Ablauf.

### Gerätesicherheit
- **Root-Detection**: `RootDetector.dart` prüft su-Binaries, Root-Apps
  (Magisk, SuperSU, KingRoot) und Emulator-Indikatoren.
- **Debugger-Detection**: TracerPid-Prüfung via `/proc/self/status`.
- **Reaktion**: Kein harter App-Abbruch — Warnung an den Nutzer +
  eingeschränkter Modus (Privacy-Hinweis).

### Screenshot-Schutz
- `FLAG_SECURE` in der Incognito-Browser-Session verhindert Screenshots
  und App-Switcher-Vorschau auf Android.
- Visueller Hinweis (`no_photography`-Icon) in der WebView-Toolbar.

### Obfuskierung
- **R8/ProGuard**: `minifyEnabled true` für alle Release-Builds.
- Keine Wildcard-`-keep`-Regeln für eigene Klassen (S-09).
- `--split-debug-info`: Symbolisierungs-Info wird separat gespeichert
  und nicht in die APK eingebettet.
- Crash-Symbolisierung: `scripts/symbolize_crash.sh <crashfile.txt>`

---

## Sicherheitsanforderungen

### Mindestanforderungen
- **Android 6.0+** (API 23): Hardware-backed Android Keystore garantiert.
- **Biometrie oder PIN/Muster**: Für Session-Entsperrung erforderlich.

### Empfehlungen für Nutzer
- Gerootete Geräte oder Emulatoren bieten keinen Hardware-Keystore-Schutz.
- FindUX zeigt einen Sicherheitshinweis wenn ein solches Gerät erkannt wird.

---

## Bekannte Einschränkungen

| Bereich | Einschränkung | Mitigierung |
|---------|--------------|-------------|
| Root | Gerootete Geräte können Hive-Dateien lesen | AES-256-Verschlüsselung |
| Emulator | Kein Hardware-Keystore | Warnung wird angezeigt |
| Clipboard | Standard-Clipboard ist nicht verschlüsselt | Auto-Clear nach 30s (`ClipboardGuard`) |
| Accessibility | AS hat Vollbild-Zugriff | Nur Volume-Key-Events abonniert |

---

## Letzte Sicherheitsprüfung

**Datum**: 2026-05-02  
**Geprüfte Bereiche**: Certificate Pinning, Datenverschlüsselung,
Manifest-Konfiguration, ProGuard-Regeln, Root-Detection, Session-Schutz.

---

*Dieses Dokument wird bei jedem Security-Release aktualisiert.*
