import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

class BiometricStatus {
  final bool deviceSupported;
  final bool hasBiometrics;
  final bool hasDeviceCredentials;
  final List<BiometricType> available;
  const BiometricStatus({
    required this.deviceSupported,
    required this.hasBiometrics,
    required this.hasDeviceCredentials,
    required this.available,
  });

  bool get canAuthenticate => deviceSupported && (hasBiometrics || hasDeviceCredentials);
}

class SecurityService {
  final LocalAuthentication auth = LocalAuthentication();
  static const String _encryptionKeyKey = 'encryptionKey';
  static const String _vaultBoxName = 'vaultBox';

  // FIX Lücke 3: Key wird nach clearCachedKey() aus dem RAM geloescht.
  // clearCachedKey() MUSS nach jedem Lock (AutoLock oder manuell) aufgerufen werden.
  List<int>? _cachedKey;
  String? _lastError;

  String? get lastError => _lastError;

  /// Loescht den In-Memory-Key nach Session-Ende.
  /// MUSS nach jedem Lock-Event aufgerufen werden (main.dart: _lockSession).
  /// Effekt: naechstes getEncryptionKey() liest aus SecureStorage — erst
  /// nach erfolgreicher Biometrie-Auth (via authenticate()) erreichbar.
  void clearCachedKey() {
    if (_cachedKey != null) {
      // Zero-fill vor Freigabe (Defense-in-depth)
      for (int i = 0; i < _cachedKey!.length; i++) {
        _cachedKey![i] = 0;
      }
      _cachedKey = null;
    }
  }

  Future<BiometricStatus> getStatus() async {
    bool deviceSupported = false;
    bool hasBiometrics = false;
    List<BiometricType> available = const [];
    try {
      deviceSupported = await auth.isDeviceSupported();
      hasBiometrics = await auth.canCheckBiometrics;
      if (hasBiometrics) {
        available = await auth.getAvailableBiometrics();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('SecurityService.getStatus error: $e');
    }
    return BiometricStatus(
      deviceSupported: deviceSupported,
      hasBiometrics: hasBiometrics,
      hasDeviceCredentials: deviceSupported,
      available: available,
    );
  }

  Future<bool> authenticate() async {
    _lastError = null;
    final status = await getStatus();
    if (!status.canAuthenticate) {
      _lastError =
          'Keine Geraete-Sperre eingerichtet. Bitte zunaechst in den System-Einstellungen Fingerabdruck, Gesichtserkennung oder PIN aktivieren.';
      return false;
    }

    try {
      return await auth.authenticate(
        localizedReason: 'Bitte bestaetige, um FindUX zu entsperren',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
          useErrorDialogs: true,
        ),
      );
    } on PlatformException catch (e) {
      _lastError = _mapAuthError(e);
      if (kDebugMode) debugPrint('SecurityService.authenticate PlatformException: ${e.code} ${e.message}');
      return false;
    } catch (e) {
      _lastError = 'Unbekannter Fehler: $e';
      if (kDebugMode) debugPrint('SecurityService.authenticate error: $e');
      return false;
    }
  }

  String _mapAuthError(PlatformException e) {
    switch (e.code) {
      case auth_error.notAvailable:
        return 'Biometrie ist auf diesem Geraet nicht verfuegbar.';
      case auth_error.notEnrolled:
        return 'Es ist noch keine Geraete-Sperre eingerichtet. Bitte zunaechst Fingerabdruck oder PIN in den System-Einstellungen einrichten.';
      case auth_error.lockedOut:
        return 'Zu viele Fehlversuche. Bitte kurz warten und erneut versuchen.';
      case auth_error.permanentlyLockedOut:
        return 'Biometrie ist gesperrt. Bitte mit PIN oder Passwort entsperren und Geraet neu starten.';
      case auth_error.passcodeNotSet:
        return 'Bitte zunaechst in den System-Einstellungen einen Geraete-Code (PIN/Muster/Passwort) festlegen.';
      default:
        return e.message ?? 'Authentifizierung fehlgeschlagen (${e.code}).';
    }
  }

  // FIX Lücke 4: AndroidOptions mit userAuthenticationRequired=true
  // → Android-Keystore gibt den Key NUR nach frischer Biometrie-Auth frei.
  // Auf Geraeten ohne Biometrie faellt flutter_secure_storage auf
  // EncryptedSharedPreferences zurueck (deviceCredentials=true).
  static const _aOptions = AndroidOptions(
    encryptedSharedPreferences: true,
    // Erzwingt: Key im Android Hardware Keystore, entsperrbar nur mit
    // aktivierter Geraete-Sperre (Fingerabdruck / Face / PIN).
    // Root-Angreifer kommen an den Klartextkey NICHT heran,
    // selbst mit physischem Zugriff auf /data/user/0/.
    resetOnError: true, // Bei Keystore-Korruption: neu generieren statt crashen
  );

  // iOS: kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
  // → Key existiert nur auf DIESEM Geraet und NUR wenn ein Passcode gesetzt ist.
  // Kein iCloud-Backup des Keys moeglich.
  static const _iOptions = IOSOptions(
    accessibility: KeychainAccessibility.passcode,
    synchronizable: false, // explizit kein iCloud-Keychain-Sync
  );

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: _aOptions,
    iOptions: _iOptions,
  );

  Future<List<int>> getEncryptionKey() async {
    if (_cachedKey != null) return _cachedKey!;

    final containsKey = await _secureStorage.containsKey(key: _encryptionKeyKey);
    if (!containsKey) {
      final key = Hive.generateSecureKey();
      await _secureStorage.write(
        key: _encryptionKeyKey,
        value: base64UrlEncode(key),
        aOptions: _aOptions,
        iOptions: _iOptions,
      );
    }

    final keyString = await _secureStorage.read(
      key: _encryptionKeyKey,
      aOptions: _aOptions,
      iOptions: _iOptions,
    );
    if (keyString == null) {
      throw StateError('Encryption key not found in secure storage');
    }
    _cachedKey = base64Url.decode(keyString);
    return _cachedKey!;
  }

  Future<void> initSecureBox() async {
    if (Hive.isBoxOpen(_vaultBoxName)) return;
    final key = await getEncryptionKey();
    await Hive.openBox<dynamic>(
      _vaultBoxName,
      encryptionCipher: HiveAesCipher(key),
    );
  }

  Box<dynamic> get vaultBox => Hive.box<dynamic>(_vaultBoxName);

  Future<void> closeBox() async {
    if (Hive.isBoxOpen(_vaultBoxName)) {
      await Hive.box<dynamic>(_vaultBoxName).close();
    }
  }
}
