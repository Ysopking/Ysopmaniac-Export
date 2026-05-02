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

  /// Authentifizierung ueberhaupt moeglich (Biometrie ODER PIN/Pattern/Passwort)?
  bool get canAuthenticate => deviceSupported && (hasBiometrics || hasDeviceCredentials);
}

class SecurityService {
  final LocalAuthentication auth = LocalAuthentication();
  static const String _encryptionKeyKey = 'encryptionKey';
  static const String _vaultBoxName = 'vaultBox';

  List<int>? _cachedKey;
  String? _lastError;

  String? get lastError => _lastError;

  /// Liefert den aktuellen Status der Geraete-Authentifizierung.
  /// Wichtig fuer das Onboarding: damit weiss der UI-Code, ob es sich
  /// lohnt, ueberhaupt einen Authenticate-Call zu starten.
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
      debugPrint('SecurityService.getStatus error: $e');
    }
    // canCheckBiometrics ist true sobald BIOMETRIC- ODER Device-Credential
    // verfuegbar ist. Wir gehen pragmatisch davon aus: wenn das Geraet
    // grundsaetzlich supported ist, kann der User mit PIN entsperren.
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
          // biometricOnly:false -> auch PIN/Pattern erlaubt, falls keine Biometrie eingerichtet
          biometricOnly: false,
          useErrorDialogs: true,
        ),
      );
    } on PlatformException catch (e) {
      _lastError = _mapAuthError(e);
      debugPrint('SecurityService.authenticate PlatformException: ${e.code} ${e.message}');
      return false;
    } catch (e) {
      _lastError = 'Unbekannter Fehler: $e';
      debugPrint('SecurityService.authenticate error: $e');
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

  Future<List<int>> getEncryptionKey() async {
    if (_cachedKey != null) return _cachedKey!;
    const secureStorage = FlutterSecureStorage();

    var containsKey = await secureStorage.containsKey(key: _encryptionKeyKey);
    if (!containsKey) {
      final key = Hive.generateSecureKey();
      await secureStorage.write(
        key: _encryptionKeyKey,
        value: base64UrlEncode(key),
      );
    }

    final keyString = await secureStorage.read(key: _encryptionKeyKey);
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
